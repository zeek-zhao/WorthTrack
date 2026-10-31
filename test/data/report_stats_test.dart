import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worthtrack/modules/finance/data/dao/transaction_dao.dart';
import 'package:worthtrack/data/db/app_database.dart';

import '../helpers/sqlite3_loader.dart';

/// issue #9 验收：报表统计聚合单测（月度/年度汇总、分类占比、逐月趋势）。
void main() {
  setUpAll(setupSqlite3ForTests);

  late AppDatabase db;
  late int a;
  late int catDining;
  late int catShopping;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    a = await db.accountDao.createAccount(
      AccountsCompanion.insert(name: '工资卡', type: AccountType.bank),
    );
    catDining = await db.categoryDao.createCategory(
      CategoriesCompanion.insert(name: '餐饮', kind: CategoryKind.expense),
    );
    catShopping = await db.categoryDao.createCategory(
      CategoriesCompanion.insert(name: '购物', kind: CategoryKind.expense),
    );

    final b = await db.accountDao.createAccount(
      AccountsCompanion.insert(name: '目标卡', type: AccountType.bank),
    );

    Future<void> t(
      TxnType type, {
      int? categoryId,
      required int amountMinor,
      required DateTime at,
    }) => db.transactionDao.createWithBalanceUpdate(
      NewTransaction(
        type: type,
        accountId: a,
        categoryId: categoryId,
        amountMinor: amountMinor,
        occurredAt: at,
      ),
    );

    Future<void> transfer({required int amountMinor, required DateTime at}) =>
        db.transactionDao.createWithBalanceUpdate(
          NewTransaction(
            type: TxnType.transfer,
            accountId: a,
            toAccountId: b,
            amountMinor: amountMinor,
            occurredAt: at,
          ),
        );

    await t(
      TxnType.expense,
      categoryId: catDining,
      amountMinor: 1000,
      at: DateTime(2026, 10, 5),
    );
    await t(
      TxnType.expense,
      categoryId: catDining,
      amountMinor: 300,
      at: DateTime(2026, 10, 6),
    );
    await t(
      TxnType.expense,
      categoryId: catShopping,
      amountMinor: 2500,
      at: DateTime(2026, 10, 10),
    );
    await t(
      TxnType.expense,
      amountMinor: 500,
      at: DateTime(2026, 10, 12),
    ); // 未分类
    await t(TxnType.income, amountMinor: 8000, at: DateTime(2026, 10, 1));
    await transfer(amountMinor: 30000, at: DateTime(2026, 10, 15));
    // 跨月/跨年数据
    await t(
      TxnType.expense,
      categoryId: catDining,
      amountMinor: 700,
      at: DateTime(2026, 9, 20),
    );
    await t(
      TxnType.expense,
      categoryId: catShopping,
      amountMinor: 2000,
      at: DateTime(2025, 12, 20),
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('月度汇总', () {
    test('收支求和，转账不计入', () async {
      final totals = await db.transactionDao
          .watchMonthTotals(DateTime(2026, 10))
          .first;
      expect(totals.expenseMinor, 1000 + 300 + 2500 + 500);
      expect(totals.incomeMinor, 8000);
      expect(totals.netMinor, 8000 - 4300);
    });

    test('不同月份互不干扰', () async {
      final sep = await db.transactionDao
          .watchMonthTotals(DateTime(2026, 9))
          .first;
      expect(sep.expenseMinor, 700);
      expect(sep.incomeMinor, 0);
    });
  });

  group('年度汇总', () {
    test('整年聚合且年份隔离', () async {
      final y2026 = await db.transactionDao.watchYearTotals(2026).first;
      expect(y2026.expenseMinor, 700 + 4300);
      final y2025 = await db.transactionDao.watchYearTotals(2025).first;
      expect(y2025.expenseMinor, 2000);
    });
  });

  group('分类占比', () {
    test('按金额降序，未分类归组，笔数正确', () async {
      final stats = await db.transactionDao
          .watchCategoryStats(DateTime(2026, 10))
          .first;
      expect(stats.map((s) => s.name).toList(), ['购物', '餐饮', '未分类']);
      expect(stats[0].totalMinor, 2500);
      expect(stats[0].count, 1);
      expect(stats[1].totalMinor, 1300);
      expect(stats[1].count, 2);
      expect(stats[2].categoryId, isNull);
      expect(stats[2].totalMinor, 500);
    });

    test('收入口径切换', () async {
      final stats = await db.transactionDao
          .watchCategoryStats(DateTime(2026, 10), kind: CategoryKind.income)
          .first;
      expect(stats, hasLength(1));
      expect(stats.single.totalMinor, 8000);
      expect(stats.single.name, '未分类');
    });

    test('任意区间版本覆盖整年', () async {
      final stats = await db.transactionDao
          .watchCategoryStatsRange(DateTime(2026), DateTime(2027))
          .first;
      final dining = stats.firstWhere((s) => s.name == '餐饮');
      expect(dining.totalMinor, 700 + 1300);
    });
  });

  group('逐月趋势', () {
    test('跨年进位且无交易月份补零', () async {
      final trend = await db.transactionDao
          .watchTrend(months: 4, anchor: DateTime(2026, 2, 10))
          .first;
      expect(trend, hasLength(4));
      expect(trend[0].month, DateTime(2025, 11));
      expect(trend[1].month, DateTime(2025, 12));
      expect(trend[1].expenseMinor, 2000);
      expect(trend[2].month, DateTime(2026, 1));
      expect(trend[2].expenseMinor, 0);
      expect(trend[3].month, DateTime(2026, 2));
      expect(trend[3].expenseMinor, 0);
    });

    test('anchor 当月纳入区间', () async {
      final trend = await db.transactionDao
          .watchTrend(months: 3, anchor: DateTime(2026, 10, 20))
          .first;
      expect(trend[2].month, DateTime(2026, 10));
      expect(trend[2].expenseMinor, 4300);
      expect(trend[2].incomeMinor, 8000);
    });
  });
}
