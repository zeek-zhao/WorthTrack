import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:worthtrack/data/dao/transaction_dao.dart';
import 'package:worthtrack/data/db/app_database.dart';
import 'package:worthtrack/data/repositories/budget_repository_impl.dart';
import 'package:worthtrack/data/repositories/recurring_repository_impl.dart';

import '../test/helpers/sqlite3_loader.dart';

/// M2 碰钱路径集成测试（issue #10/#11）：
/// 周期账单补生成 + 预算消耗，覆盖完整数据链路 DAO → Drift → SQLite。
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

  testWidgets('周期账单连漏三期 → 补生成三期且余额正确', (tester) async {
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

    // 生成的流水可查回。
    final txns = await db.transactionDao
        .watchByFilter(
          TxnFilter(start: DateTime(2026, 7), end: DateTime(2026, 11)),
        )
        .first;
    expect(txns, hasLength(3));
    expect(txns.every((t) => t.amountMinor == 150000), isTrue);
  });

  testWidgets('预算消耗：当月支出计入、跨月不计入', (tester) async {
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
}
