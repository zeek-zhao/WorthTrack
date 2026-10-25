import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worthtrack/data/dao/transaction_dao.dart';
import 'package:worthtrack/data/db/app_database.dart';
import 'package:worthtrack/data/repositories/budget_repository_impl.dart';

import '../helpers/sqlite3_loader.dart';

/// issue #10 验收：预算 upsert 幂等、跨月消耗边界、超支判定。
void main() {
  setUpAll(setupSqlite3ForTests);

  late AppDatabase db;
  late BudgetRepositoryImpl repo;
  late int a;
  late int catA;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = BudgetRepositoryImpl(db.budgetDao, db.transactionDao);
    a = await db.accountDao.createAccount(
      AccountsCompanion.insert(name: '现金', type: AccountType.cash),
    );
    catA = await db.categoryDao.createCategory(
      CategoriesCompanion.insert(name: '餐饮', kind: CategoryKind.expense),
    );
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> expense(int amountMinor, DateTime at) {
    return db.transactionDao.createWithBalanceUpdate(
      NewTransaction(
        type: TxnType.expense,
        accountId: a,
        categoryId: catA,
        amountMinor: amountMinor,
        occurredAt: at,
      ),
    );
  }

  test('upsert：同月同分类只保留一行，金额取最新', () async {
    await repo.upsertBudget(
      DateTime(2026, 10, 15),
      categoryId: catA,
      amountMinor: 1000,
    );
    await repo.upsertBudget(
      DateTime(2026, 10, 1),
      categoryId: catA,
      amountMinor: 2000,
    );
    final rows = await db.select(db.budgets).get();
    expect(rows, hasLength(1));
    expect(rows.single.amountMinor, 2000);
    // 月份归一化到当月 1 日。
    expect(rows.single.month, DateTime(2026, 10));
  });

  test('跨月边界：预算只统计归属月（左闭右开）', () async {
    await repo.upsertBudget(
      DateTime(2026, 10),
      categoryId: catA,
      amountMinor: 1000,
    );
    await expense(500, DateTime(2026, 9, 30, 23, 59)); // 九月 → 不计
    await expense(300, DateTime(2026, 10, 1, 0, 0)); // 十月 → 计
    await expense(400, DateTime(2026, 10, 31, 23, 59)); // 十月 → 计
    await expense(100, DateTime(2026, 11, 1, 0, 0)); // 十一月 → 不计

    final statuses = await repo.watchBudgetStatuses(DateTime(2026, 10)).first;
    expect(statuses, hasLength(1));
    final s = statuses.single;
    expect(s.spentMinor, 700);
    expect(s.budget.amountMinor, 1000);
    expect(s.overBudget, isFalse);
    expect(s.remainingMinor, 300);
    expect(s.usage, closeTo(0.7, 1e-9));
  });

  test('超支判定与负剩余', () async {
    await repo.upsertBudget(
      DateTime(2026, 10),
      categoryId: catA,
      amountMinor: 1000,
    );
    await expense(1500, DateTime(2026, 10, 5));

    final statuses = await repo.watchBudgetStatuses(DateTime(2026, 10)).first;
    final s = statuses.single;
    expect(s.overBudget, isTrue);
    expect(s.remainingMinor, -500);
    expect(s.usage, greaterThan(1.0));
  });

  test('无交易分类的预算消耗为 0', () async {
    await repo.upsertBudget(
      DateTime(2026, 10),
      categoryId: catA,
      amountMinor: 1000,
    );
    final statuses = await repo.watchBudgetStatuses(DateTime(2026, 10)).first;
    expect(statuses.single.spentMinor, 0);
    expect(statuses.single.usage, 0);
  });

  test('删除预算后不再出现在状态列表', () async {
    await repo.upsertBudget(
      DateTime(2026, 10),
      categoryId: catA,
      amountMinor: 1000,
    );
    final before = await repo.watchBudgetStatuses(DateTime(2026, 10)).first;
    await repo.deleteBudget(before.single.budget.id);
    final after = await repo.watchBudgetStatuses(DateTime(2026, 10)).first;
    expect(after, isEmpty);
  });
}
