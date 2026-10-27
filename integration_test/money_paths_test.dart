import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:fast_gbk/fast_gbk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:worthtrack/data/dao/transaction_dao.dart';
import 'package:worthtrack/data/db/app_database.dart';
import 'package:worthtrack/data/price/tencent_price_provider.dart';
import 'package:worthtrack/data/repositories/budget_repository_impl.dart';
import 'package:worthtrack/data/repositories/position_repository_impl.dart';
import 'package:worthtrack/data/repositories/recurring_repository_impl.dart';

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
}
