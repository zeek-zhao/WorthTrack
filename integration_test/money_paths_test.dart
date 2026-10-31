import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:fast_gbk/fast_gbk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:worthtrack/core/backup/database_backup_repository.dart';
import 'package:worthtrack/modules/finance/data/dao/transaction_dao.dart';
import 'package:worthtrack/data/db/app_database.dart';
import 'package:worthtrack/core/pin/pin_store.dart';
import 'package:worthtrack/modules/finance/data/price/tencent_price_provider.dart';
import 'package:worthtrack/modules/finance/data/repositories/budget_repository_impl.dart';
import 'package:worthtrack/modules/finance/data/repositories/export_repository_impl.dart';
import 'package:worthtrack/modules/finance/data/repositories/net_worth_repository_impl.dart';
import 'package:worthtrack/core/pin/pin_repository_impl.dart';
import 'package:worthtrack/modules/finance/data/repositories/position_repository_impl.dart';
import 'package:worthtrack/modules/finance/data/repositories/recurring_repository_impl.dart';
import 'package:worthtrack/modules/finance/domain/csv_export.dart';
import 'package:worthtrack/modules/finance/domain/price_provider.dart';

import '../test/helpers/sqlite3_loader.dart';

/// 构造一条腾讯行情响应（字段位置与真实响应一致，GBK 编码）。
String tencentLine(
  String symbol,
  String name,
  String price, {
  String time = '20261027161452',
}) {
  final fields = <String>[
    symbol.startsWith('sh') ? '1' : '51',
    name,
    symbol.substring(2),
    price,
    price,
    price,
    '1000',
  ];
  while (fields.length < 30) {
    fields.add('');
  }
  fields
    ..add(time)
    ..add('0.00')
    ..add('0.00')
    ..add(price)
    ..add(price);
  return 'v_$symbol="${fields.join('~')}";';
}

/// M1 碰钱路径集成测试（issue #8）。
///
/// 覆盖完整数据链路：DAO → Drift → SQLite（内存库），
/// 在 CI 与真机上都以同一条用例集跑通。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(setupSqlite3ForTests);

  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('建账户 → 记支出 → 余额变化正确', (tester) async {
    final accountId = await db.accountDao.createAccount(
      AccountsCompanion.insert(
        name: '现金钱包',
        type: AccountType.cash,
        balanceMinor: Value(100000), // ¥1000.00
      ),
    );

    await db.transactionDao.createWithBalanceUpdate(
      NewTransaction(
        type: TxnType.expense,
        accountId: accountId,
        amountMinor: 2580, // ¥25.80
        occurredAt: DateTime(2026, 10, 25, 12),
      ),
    );

    final account = await db.accountDao.getById(accountId);
    expect(account!.balanceMinor, 97420);

    // 流水可查回且金额正确。
    final txns = await db.transactionDao.watchByMonth(DateTime(2026, 10)).first;
    expect(txns, hasLength(1));
    expect(txns.first.amountMinor, 2580);
  });

  testWidgets('两账户转账 → 双方余额正确', (tester) async {
    final from = await db.accountDao.createAccount(
      AccountsCompanion.insert(
        name: '银行卡',
        type: AccountType.bank,
        balanceMinor: const Value(500000),
      ),
    );
    final to = await db.accountDao.createAccount(
      AccountsCompanion.insert(name: '零钱', type: AccountType.cash),
    );

    await db.transactionDao.createWithBalanceUpdate(
      NewTransaction(
        type: TxnType.transfer,
        accountId: from,
        toAccountId: to,
        amountMinor: 150000, // ¥1500.00
        occurredAt: DateTime(2026, 10, 25, 12),
      ),
    );

    expect((await db.accountDao.getById(from))!.balanceMinor, 350000);
    expect((await db.accountDao.getById(to))!.balanceMinor, 150000);
    // 总资产守恒。
    expect(await db.accountDao.watchTotalBalanceMinor().first, 500000);
  });

  testWidgets('删除交易 → 余额回滚正确', (tester) async {
    final accountId = await db.accountDao.createAccount(
      AccountsCompanion.insert(
        name: '信用卡',
        type: AccountType.credit,
        balanceMinor: const Value(0),
      ),
    );
    final incomeId = await db.transactionDao.createWithBalanceUpdate(
      NewTransaction(
        type: TxnType.income,
        accountId: accountId,
        amountMinor: 88000,
        occurredAt: DateTime(2026, 10, 25, 9),
      ),
    );
    await db.transactionDao.createWithBalanceUpdate(
      NewTransaction(
        type: TxnType.expense,
        accountId: accountId,
        amountMinor: 38000,
        occurredAt: DateTime(2026, 10, 25, 10),
      ),
    );
    expect((await db.accountDao.getById(accountId))!.balanceMinor, 50000);

    // 删除收入那笔 → 回滚到只剩支出的状态。
    await db.transactionDao.deleteWithBalanceReversal(incomeId);
    expect((await db.accountDao.getById(accountId))!.balanceMinor, -38000);

    final txns = await db.transactionDao.watchByMonth(DateTime(2026, 10)).first;
    expect(txns, hasLength(1));
    expect(txns.first.type, TxnType.expense);
  });

  // ===== M2 碰钱路径（issue #10/#11）=====
  // 注：CI 的 Linux host 环境下第二个集成测试文件无法启动应用
  // （"Error waiting for a debug connection"，稳定复现），
  // 因此全部碰钱路径集成用例集中在单文件内，一次应用启动跑完。

  testWidgets('周期账单连漏三期 → 补生成三期且余额正确、重复执行幂等', (tester) async {
    final accountId = await db.accountDao.createAccount(
      AccountsCompanion.insert(
        name: '银行卡',
        type: AccountType.bank,
        balanceMinor: const Value(500000), // ¥5000.00
      ),
    );
    final catId = await db.categoryDao.createCategory(
      CategoriesCompanion.insert(name: '居住', kind: CategoryKind.expense),
    );

    final repo = RecurringRepositoryImpl(db.recurringDao, db.transactionDao);
    await repo.addRule(
      name: '房租',
      type: TxnType.expense,
      accountId: accountId,
      categoryId: catId,
      amountMinor: 150000, // ¥1500.00
      frequency: RecurFrequency.monthly,
      startDate: DateTime(2026, 7, 10),
    );

    // 模拟三个月未打开应用后启动（10 月 5 日）。
    final generated = await repo.catchUp(DateTime(2026, 10, 5, 12));
    expect(generated, 3);

    final account = await db.accountDao.getById(accountId);
    expect(account!.balanceMinor, 500000 - 150000 * 3);

    // 再次启动不重复生成。
    expect(await repo.catchUp(DateTime(2026, 10, 5, 12)), 0);

    // 生成的流水可查回且逐期落在 10 日。
    final txns = await db.transactionDao
        .watchByFilter(
          TxnFilter(start: DateTime(2026, 7), end: DateTime(2026, 11)),
        )
        .first;
    expect(txns, hasLength(3));
    expect(txns.every((t) => t.amountMinor == 150000), isTrue);
    expect(txns.map((t) => t.occurredAt.day), everyElement(10));
  });

  testWidgets('预算消耗：当月支出计入、跨月不计入、超支判定', (tester) async {
    final accountId = await db.accountDao.createAccount(
      AccountsCompanion.insert(
        name: '现金',
        type: AccountType.cash,
        balanceMinor: const Value(100000),
      ),
    );
    final catId = await db.categoryDao.createCategory(
      CategoriesCompanion.insert(name: '餐饮', kind: CategoryKind.expense),
    );
    final repo = BudgetRepositoryImpl(db.budgetDao, db.transactionDao);
    await repo.upsertBudget(
      DateTime(2026, 10),
      categoryId: catId,
      amountMinor: 10000, // ¥100.00
    );

    Future<void> spend(int minor, DateTime at) =>
        db.transactionDao.createWithBalanceUpdate(
          NewTransaction(
            type: TxnType.expense,
            accountId: accountId,
            categoryId: catId,
            amountMinor: minor,
            occurredAt: at,
          ),
        );

    await spend(3000, DateTime(2026, 9, 28, 12)); // 九月
    await spend(6000, DateTime(2026, 10, 20, 12)); // 十月
    await spend(500, DateTime(2026, 11, 2, 12)); // 十一月

    final statuses = await repo.watchBudgetStatuses(DateTime(2026, 10)).first;
    expect(statuses, hasLength(1));
    expect(statuses.single.spentMinor, 6000);
    expect(statuses.single.overBudget, isFalse);

    // 超支场景：再花 5000 → 11000 > 10000。
    await spend(5000, DateTime(2026, 10, 25, 12));
    final after = await repo.watchBudgetStatuses(DateTime(2026, 10)).first;
    expect(after.single.overBudget, isTrue);
    expect(after.single.remainingMinor, -1000);
  });

  // ===== M3 碰钱路径（issue #13/#14）=====

  /// 用 mock HTTP 驱动真实链路：
  /// GBK 响应字节 → 解码 → 解析 → price_cache → 估值流 → 市值/盈亏。
  testWidgets('刷新行情（mock HTTP）→ 缓存价落库、市值与盈亏正确', (tester) async {
    final body =
        '${tencentLine('sh600519', '贵州茅台', '1355.90')}'
        '${tencentLine('sz159915', '创业板ETF', '2.563')}';
    final repo = PositionRepositoryImpl(
      db.positionDao,
      TencentPriceProvider(
        client: MockClient((request) async {
          expect(
            request.url.toString(),
            'https://qt.gtimg.cn/q=sh600519,sz159915',
          );
          return http.Response.bytes(gbk.encode(body), 200);
        }),
      ),
    );

    await repo.createPosition(
      market: Market.sh,
      code: '600519',
      name: '贵州茅台',
      sharesCent: 15000, // 150.00 份
      costPriceMinor: 160000, // 成本 1600.00
    );
    await repo.createPosition(
      market: Market.sz,
      code: '159915',
      name: '创业板ETF',
      sharesCent: 100000, // 1000.00 份
      costPriceMinor: 300, // 成本 3.00 元
    );

    // 刷新前：无价，市值为空。
    expect(
      (await repo.watchValuations().first).every((v) => !v.hasPrice),
      isTrue,
    );

    final report = await repo.refreshPrices();
    expect(report.updated, 2);
    expect(report.failed, 0);

    final valuations = await repo.watchValuations().first;
    final moutai = valuations.firstWhere((v) => v.symbol == 'sh600519');
    expect(moutai.priceMinor, 135590);
    expect(moutai.marketValueMinor, 20338500); // 150 × 1355.90 元
    expect(moutai.profitMinor, 20338500 - 24000000); // 浮亏

    final etf = valuations.firstWhere((v) => v.symbol == 'sz159915');
    expect(etf.priceMinor, 256); // 2.563 → 256 分（分精度四舍五入）
    expect(etf.marketValueMinor, 256000); // 1000 × 2.56 元

    // 缓存价落库，且时间取行情时间（不是本地刷新时刻）。
    final cached = await db.positionDao.getPrice('sh600519');
    expect(cached!.priceMinor, 135590);
    expect(cached.updatedAt, DateTime(2026, 10, 27, 16, 14, 52));
  });

  testWidgets('刷新遇停牌 → 沿用缓存价，市值不被清零', (tester) async {
    final repo = PositionRepositoryImpl(
      db.positionDao,
      TencentPriceProvider(
        client: MockClient(
          (_) async => http.Response.bytes(
            gbk.encode(tencentLine('sh600519', '贵州茅台', '0.00')),
            200,
          ),
        ),
      ),
    );
    await repo.createPosition(
      market: Market.sh,
      code: '600519',
      name: '贵州茅台',
      sharesCent: 15000,
      costPriceMinor: 160000,
    );
    // 先有一份手动录入的缓存价。
    await repo.setPrice(market: Market.sh, code: '600519', priceMinor: 170000);

    final report = await repo.refreshPrices();

    expect(report.suspended, 1);
    expect(report.updated, 0);
    final v = (await repo.watchValuations().first).single;
    expect(v.priceMinor, 170000); // 沿用缓存价
    expect(v.marketValueMinor, 25500000);
  });

  testWidgets('净资产：支出降低、转账不变、投资市值计入且曲线末点等于当前值', (tester) async {
    final created = DateTime(2026, 8, 1);
    final bank = await db.accountDao.createAccount(
      AccountsCompanion.insert(
        name: '工资卡',
        type: AccountType.bank,
        balanceMinor: const Value(1000000), // ¥10000.00
        createdAt: Value(created),
      ),
    );
    final cash = await db.accountDao.createAccount(
      AccountsCompanion.insert(
        name: '零钱',
        type: AccountType.cash,
        createdAt: Value(created),
      ),
    );
    await db.accountDao.createAccount(
      AccountsCompanion.insert(
        name: '券商',
        type: AccountType.investment,
        balanceMinor: const Value(300000),
        createdAt: Value(created),
      ),
    );

    final positionRepo = PositionRepositoryImpl(
      db.positionDao,
      _NoopPriceProvider(),
    );
    final netWorthRepo = NetWorthRepositoryImpl(
      db.accountDao,
      db.transactionDao,
      positionRepo,
      now: () => DateTime(2026, 10, 28),
    );

    // 初始：现金类 10000，投资账户余额 3000 不计入。
    var overview = await netWorthRepo.watchOverview(months: 3).first;
    expect(overview.cashMinor, 1000000);
    expect(overview.investmentMinor, 0);
    expect(overview.netWorthMinor, 1000000);
    expect(overview.investmentAccountBalanceMinor, 300000);

    // 转账：内部搬运，净资产不变。
    await db.transactionDao.createWithBalanceUpdate(
      NewTransaction(
        type: TxnType.transfer,
        accountId: bank,
        toAccountId: cash,
        amountMinor: 200000,
        occurredAt: DateTime(2026, 10, 5),
      ),
    );
    overview = await netWorthRepo.watchOverview(months: 3).first;
    expect(overview.netWorthMinor, 1000000);

    // 支出：净资产下降。
    await db.transactionDao.createWithBalanceUpdate(
      NewTransaction(
        type: TxnType.expense,
        accountId: bank,
        amountMinor: 2580,
        occurredAt: DateTime(2026, 10, 6),
      ),
    );
    overview = await netWorthRepo.watchOverview(months: 3).first;
    expect(overview.cashMinor, 997420);

    // 加一只持仓并给价：市值计入净资产（本月才建仓，历史月份不计入）。
    await db.positionDao.createPosition(
      PositionsCompanion.insert(
        market: Market.sh,
        code: '600519',
        name: '贵州茅台',
        sharesCent: 15000,
        costPriceMinor: 160000,
        createdAt: Value(DateTime(2026, 10, 2)),
      ),
    );
    await positionRepo.setPrice(
      market: Market.sh,
      code: '600519',
      priceMinor: 170000,
    );
    overview = await netWorthRepo.watchOverview(months: 3).first;
    expect(overview.investmentMinor, 25500000);
    expect(overview.netWorthMinor, 997420 + 25500000);

    // 曲线末点（本月末）等于当前净资产；8、9 月不含本月才建的仓位。
    expect(overview.series.last.month, DateTime(2026, 10));
    expect(overview.series.last.netWorthMinor, overview.netWorthMinor);
    expect(overview.series.first.month, DateTime(2026, 8));
    expect(overview.series.first.netWorthMinor, 1000000);
  });

  testWidgets('忘记 PIN 重置不清数据：PIN 文件删除，账目原样保留', (tester) async {
    final accountId = await db.accountDao.createAccount(
      AccountsCompanion.insert(
        name: '工资卡',
        type: AccountType.bank,
        balanceMinor: Value(500000),
      ),
    );
    await db.transactionDao.createWithBalanceUpdate(
      NewTransaction(
        type: TxnType.expense,
        accountId: accountId,
        amountMinor: 12345,
        occurredAt: DateTime(2026, 10, 20, 9),
      ),
    );

    final tempDir = await Directory.systemTemp.createTemp('wt_pin_it_');
    addTearDown(() async {
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    });
    final pinRepo = PinRepositoryImpl(
      FilePinStore(directory: () async => tempDir),
      iterations: 20,
    );

    await pinRepo.setPin('123456');
    expect(await pinRepo.hasPin(), isTrue);
    expect(await pinRepo.verifyPin('123456'), isTrue);

    // 「忘记 PIN」：清掉凭据即可，数据库一个字节都不动。
    await pinRepo.clearPin();
    expect(await pinRepo.hasPin(), isFalse);
    expect(
      File('${tempDir.path}/${FilePinStore.fileName}').existsSync(),
      isFalse,
    );

    final account = await db.accountDao.getById(accountId);
    expect(account, isNotNull);
    expect(account!.balanceMinor, 487655);
    final txns = await db.transactionDao.watchByMonth(DateTime(2026, 10)).first;
    expect(txns, hasLength(1));
    expect(txns.first.amountMinor, 12345);
  });

  // ===== M4 碰钱路径（issue #18）=====

  /// 备份 → 清空 → 恢复：三个环节串起来才是「数据不丢」，
  /// 单测里恢复成功不代表导出的那份文件真能还原（可能只测了半条链路）。
  testWidgets('导出备份 → 清空账本 → 从备份恢复 → 数据逐项一致', (tester) async {
    final tempDir = await Directory.systemTemp.createTemp('wt_backup_it_');
    addTearDown(() async {
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    });

    final accountId = await db.accountDao.createAccount(
      AccountsCompanion.insert(
        name: '工资卡',
        type: AccountType.bank,
        balanceMinor: const Value(1000000), // ¥10000.00
      ),
    );
    await db.transactionDao.createWithBalanceUpdate(
      NewTransaction(
        type: TxnType.expense,
        accountId: accountId,
        amountMinor: 2580, // ¥25.80
        note: '午饭',
        occurredAt: DateTime(2026, 10, 20, 12),
      ),
    );
    await db.positionDao.createPosition(
      PositionsCompanion.insert(
        market: Market.sh,
        code: '600519',
        name: '贵州茅台',
        sharesCent: 15000, // 150.00 份
        costPriceMinor: 160000,
      ),
    );
    await db.positionDao.upsertPrice(
      'sh600519',
      135590,
      at: DateTime(2026, 10, 27, 16, 14),
    );

    final repo = DatabaseBackupRepository(
      db,
      tempDirectory: () async => tempDir,
    );
    final bytes = await repo.exportBytes();
    final backupPath = '${tempDir.path}/backup.sqlite3';
    await File(backupPath).writeAsBytes(bytes, flush: true);

    // 清空（等价于换机 / 误删库）。
    for (final table in [
      'transactions',
      'budgets',
      'recurring_rules',
      'positions',
      'price_cache',
      'categories',
      'accounts',
    ]) {
      await db.customStatement('DELETE FROM "$table"');
    }
    expect(await db.accountDao.getById(accountId), isNull);

    final inspection = await repo.inspect(backupPath);
    expect(inspection.canRestore, isTrue);
    expect(inspection.accountCount, 1);
    expect(inspection.transactionCount, 1);
    expect(inspection.positionCount, 1);

    await repo.restoreFrom(backupPath);

    // 余额、流水、持仓、缓存价逐项回到备份时的样子。
    final account = await db.accountDao.getById(accountId);
    expect(account, isNotNull);
    expect(account!.name, '工资卡');
    expect(account.balanceMinor, 997420);

    final txns = await db.transactionDao.watchByMonth(DateTime(2026, 10)).first;
    expect(txns, hasLength(1));
    expect(txns.first.amountMinor, 2580);
    expect(txns.first.note, '午饭');

    final positions = await db.positionDao.getActivePositions();
    expect(positions, hasLength(1));
    expect(positions.single.code, '600519');
    expect(positions.single.sharesCent, 15000);

    final price = await db.positionDao.getPrice('sh600519');
    expect(price!.priceMinor, 135590);
    expect(price.updatedAt, DateTime(2026, 10, 27, 16, 14));
  });

  // ===== M4 碰钱路径（issue #19）=====

  /// CSV 是「离开应用」的出口，编码错了用户在 Excel 里看到的全是乱码，
  /// 因此这里连 BOM 字节一起断言，而不只是看行数。
  testWidgets('导出流水 CSV：BOM + 列顺序 + 中文与逗号转义', (tester) async {
    final bank = await db.accountDao.createAccount(
      AccountsCompanion.insert(
        name: '工资卡',
        type: AccountType.bank,
        balanceMinor: const Value(1000000),
      ),
    );
    final cash = await db.accountDao.createAccount(
      AccountsCompanion.insert(name: '零钱', type: AccountType.cash),
    );
    final food = await db.categoryDao.createCategory(
      CategoriesCompanion.insert(name: '餐饮', kind: CategoryKind.expense),
    );
    await db.transactionDao.createWithBalanceUpdate(
      NewTransaction(
        type: TxnType.expense,
        accountId: bank,
        categoryId: food,
        amountMinor: 2580, // ¥25.80
        note: '午饭,加饮料',
        occurredAt: DateTime(2026, 10, 20, 12),
      ),
    );
    await db.transactionDao.createWithBalanceUpdate(
      NewTransaction(
        type: TxnType.transfer,
        accountId: bank,
        toAccountId: cash,
        amountMinor: 100000, // ¥1000.00
        occurredAt: DateTime(2026, 10, 21, 9),
      ),
    );

    final repo = ExportRepositoryImpl(
      db.transactionDao,
      now: () => DateTime(2026, 10, 28, 22, 45),
    );
    final export = await repo.transactionsCsv();

    expect(export.rowCount, 2);
    expect(export.bytes.sublist(0, 3), csvUtf8Bom);

    final lines = utf8.decode(export.bytes.sublist(3)).split('\r\n');
    expect(lines.first, '时间,类型,账户,分类,金额,备注');
    expect(lines[1], '2026-10-20 12:00,支出,工资卡,餐饮,25.80,"午饭,加饮料"');
    expect(lines[2], '2026-10-21 09:00,转账,工资卡 → 零钱,,1000.00,');
  });

  // ===== M4 碰钱路径（issue #21）=====

  /// 编辑交易是最容易把余额算错的一条路径：必须「先冲销旧影响、再应用新影响」，
  /// 换账户时两个账户都得回到正确值，改类型时符号也要跟着翻。
  testWidgets('编辑交易：改金额 + 换账户 + 改类型，余额始终正确', (tester) async {
    final bank = await db.accountDao.createAccount(
      AccountsCompanion.insert(
        name: '工资卡',
        type: AccountType.bank,
        balanceMinor: const Value(1000000), // ¥10000.00
      ),
    );
    final cash = await db.accountDao.createAccount(
      AccountsCompanion.insert(
        name: '零钱',
        type: AccountType.cash,
        balanceMinor: const Value(100000), // ¥1000.00
      ),
    );
    final food = await db.categoryDao.createCategory(
      CategoriesCompanion.insert(name: '餐饮', kind: CategoryKind.expense),
    );

    final txnId = await db.transactionDao.createWithBalanceUpdate(
      NewTransaction(
        type: TxnType.expense,
        accountId: bank,
        categoryId: food,
        amountMinor: 2580, // ¥25.80
        occurredAt: DateTime(2026, 10, 20, 12),
      ),
    );
    expect((await db.accountDao.getById(bank))!.balanceMinor, 997420);

    // 改成「从零钱付 ¥30.00」：工资卡要完全冲销，零钱要扣掉新金额。
    await db.transactionDao.updateWithBalanceAdjust(
      txnId,
      NewTransaction(
        type: TxnType.expense,
        accountId: cash,
        categoryId: food,
        amountMinor: 3000,
        note: '改成零钱付',
        occurredAt: DateTime(2026, 10, 20, 12),
      ),
    );
    expect((await db.accountDao.getById(bank))!.balanceMinor, 1000000);
    expect((await db.accountDao.getById(cash))!.balanceMinor, 97000);

    // 再改成「收入 ¥30.00」：先退掉支出再记收入，零钱应回到 1030.00。
    await db.transactionDao.updateWithBalanceAdjust(
      txnId,
      NewTransaction(
        type: TxnType.income,
        accountId: cash,
        amountMinor: 3000,
        occurredAt: DateTime(2026, 10, 20, 12),
      ),
    );
    expect((await db.accountDao.getById(cash))!.balanceMinor, 103000);
    expect((await db.accountDao.getById(bank))!.balanceMinor, 1000000);

    // 全表只有一条流水（编辑不是「新增一条」）。
    final txns = await db.transactionDao.watchByMonth(DateTime(2026, 10)).first;
    expect(txns, hasLength(1));
    expect(txns.single.type, TxnType.income);
  });

  /// 验收标准 5「断网状态下以缓存价查看投资盈亏仍然可用」的自动化版本：
  /// 行情整批失败时一条缓存都不许动，记账链路也不受影响。
  testWidgets('断网刷新行情 → 缓存价不动、市值照算、记账照常', (tester) async {
    final repo = PositionRepositoryImpl(
      db.positionDao,
      TencentPriceProvider(
        client: MockClient(
          (_) async => throw SocketException('network is unreachable'),
        ),
      ),
    );
    await repo.createPosition(
      market: Market.sh,
      code: '600519',
      name: '贵州茅台',
      sharesCent: 15000, // 150.00 份
      costPriceMinor: 160000,
    );
    await repo.setPrice(market: Market.sh, code: '600519', priceMinor: 170000);

    final report = await repo.refreshPrices();
    expect(report.failed, 1);
    expect(report.updated, 0);
    expect(report.suspended, 0);

    // 缓存价原封不动，市值与盈亏仍可计算。
    final cached = await db.positionDao.getPrice('sh600519');
    expect(cached!.priceMinor, 170000);
    final valuation = (await repo.watchValuations().first).single;
    expect(valuation.priceMinor, 170000);
    expect(valuation.marketValueMinor, 25500000); // 150 × 1700.00 元
    expect(valuation.profitMinor, 25500000 - 24000000);

    // 断网不影响记账。
    final accountId = await db.accountDao.createAccount(
      AccountsCompanion.insert(
        name: '现金',
        type: AccountType.cash,
        balanceMinor: const Value(100000),
      ),
    );
    await db.transactionDao.createWithBalanceUpdate(
      NewTransaction(
        type: TxnType.expense,
        accountId: accountId,
        amountMinor: 2580,
        occurredAt: DateTime(2026, 10, 20, 12),
      ),
    );
    expect((await db.accountDao.getById(accountId))!.balanceMinor, 97420);
  });
}

/// 净资产用例不涉及行情，用空实现占位。
class _NoopPriceProvider implements PriceProvider {
  @override
  Future<Map<String, Quote>> fetchQuotes(List<String> symbols) async =>
      const {};
}
