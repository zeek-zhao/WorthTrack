import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worthtrack/modules/finance/data/dao/transaction_dao.dart';
import 'package:worthtrack/data/db/app_database.dart';
import 'package:worthtrack/modules/finance/data/repositories/net_worth_repository_impl.dart';
import 'package:worthtrack/modules/finance/data/repositories/position_repository_impl.dart';
import 'package:worthtrack/modules/finance/domain/price_provider.dart';

import '../helpers/sqlite3_loader.dart';

/// 本文件不测行情，行情源用空实现占位。
class _NoopPriceProvider implements PriceProvider {
  @override
  Future<Map<String, Quote>> fetchQuotes(List<String> symbols) async =>
      const {};
}

/// issue #16 验收：资产总览（现金+储蓄+投资）与净资产序列（真 Drift 内存库）。
void main() {
  setUpAll(setupSqlite3ForTests);

  late AppDatabase db;
  late NetWorthRepositoryImpl repo;

  /// 固定"今天"，避免跨月边界导致序列长度抖动。
  final today = DateTime(2026, 10, 28);
  final monthStart = DateTime(2026, 8, 1);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = NetWorthRepositoryImpl(
      db.accountDao,
      db.transactionDao,
      PositionRepositoryImpl(db.positionDao, _NoopPriceProvider()),
      now: () => today,
    );
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> addAccount(
    String name,
    AccountType type,
    int balanceMinor, {
    DateTime? createdAt,
  }) {
    return db.accountDao.createAccount(
      AccountsCompanion.insert(
        name: name,
        type: type,
        balanceMinor: Value(balanceMinor),
        createdAt: Value(createdAt ?? monthStart),
      ),
    );
  }

  Future<int> addPosition({
    String code = '600519',
    int sharesCent = 15000,
    int costPriceMinor = 160000,
    DateTime? createdAt,
  }) {
    return db.positionDao.createPosition(
      PositionsCompanion.insert(
        market: Market.sh,
        code: code,
        name: '测试持仓',
        sharesCent: sharesCent,
        costPriceMinor: costPriceMinor,
        createdAt: Value(createdAt ?? monthStart),
      ),
    );
  }

  group('资产总览', () {
    test('现金+储蓄+投资汇总：信用卡负余额抵减，投资账户余额不计入', () async {
      await addAccount('零钱', AccountType.cash, 10000);
      await addAccount('工资卡', AccountType.bank, 500000);
      await addAccount('信用卡', AccountType.credit, -120000);
      await addAccount('券商', AccountType.investment, 300000);
      final positionId = await addPosition();
      await db.positionDao.upsertPrice('sh600519', 170000);

      final overview = await repo.watchOverview().first;

      expect(overview.cashMinor, 390000); // 100 + 5000 - 1200
      expect(overview.investmentMinor, 25500000); // 150 份 × 1700
      expect(overview.netWorthMinor, 390000 + 25500000);
      expect(overview.investmentAccountBalanceMinor, 300000);
      expect(overview.unpricedPositionCount, 0);
      expect(positionId, greaterThan(0));
    });

    test('未录价持仓计入提示但不计入市值', () async {
      await addAccount('工资卡', AccountType.bank, 100000);
      await addPosition();

      final overview = await repo.watchOverview().first;

      expect(overview.investmentMinor, 0);
      expect(overview.unpricedPositionCount, 1);
      expect(overview.netWorthMinor, 100000);
    });

    test('归档账户与归档持仓不计入总览', () async {
      final accId = await addAccount('工资卡', AccountType.bank, 100000);
      final other = await addAccount('旧卡', AccountType.bank, 50000);
      final positionId = await addPosition();
      await db.positionDao.upsertPrice('sh600519', 170000);

      await db.accountDao.archiveAccount(other);
      await db.positionDao.archivePosition(positionId);

      final overview = await repo.watchOverview().first;

      expect(overview.cashMinor, 100000);
      expect(overview.investmentMinor, 0);
      expect(accId, greaterThan(0));
    });

    test('改价后总览随之更新（同一订阅后续事件）', () async {
      await addAccount('工资卡', AccountType.bank, 100000);
      await addPosition();

      final first = await repo.watchOverview().first;
      expect(first.netWorthMinor, 100000);

      await db.positionDao.upsertPrice('sh600519', 170000);
      final after = await repo.watchOverview().first;
      expect(after.netWorthMinor, 100000 + 25500000);
    });
  });

  group('净资产序列', () {
    test('支出发生前的月份净资产更高（反向回溯）', () async {
      final accId = await addAccount('工资卡', AccountType.bank, 100000);
      await db.transactionDao.createWithBalanceUpdate(
        NewTransaction(
          type: TxnType.expense,
          accountId: accId,
          amountMinor: 30000,
          occurredAt: DateTime(2026, 10, 5),
        ),
      );

      final overview = await repo.watchOverview(months: 3).first;
      final series = overview.series;

      expect(series.length, 3);
      expect(series.last.month, DateTime(2026, 10));
      expect(series.last.netWorthMinor, 70000);
      // 8、9 月还没花这 300 元。
      expect(series[0].netWorthMinor, 100000);
      expect(series[1].netWorthMinor, 100000);
    });

    test('本月才建的持仓不计入历史月份', () async {
      await addAccount('工资卡', AccountType.bank, 100000);
      await addPosition(createdAt: DateTime(2026, 10, 2));
      await db.positionDao.upsertPrice('sh600519', 170000);

      final series = (await repo.watchOverview(months: 3).first).series;

      expect(series[0].netWorthMinor, 100000);
      expect(series[1].netWorthMinor, 100000);
      expect(series[2].netWorthMinor, 100000 + 25500000);
    });

    test('空账本返回空序列', () async {
      final overview = await repo.watchOverview().first;

      expect(overview.series, isEmpty);
      expect(overview.isEmpty, isTrue);
    });
  });
}
