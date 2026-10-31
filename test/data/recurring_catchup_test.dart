import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worthtrack/modules/finance/data/dao/transaction_dao.dart';
import 'package:worthtrack/data/db/app_database.dart';
import 'package:worthtrack/modules/finance/data/repositories/recurring_repository_impl.dart';

import '../helpers/sqlite3_loader.dart';

/// issue #11 验收：启动补生成（连漏三期只生成三期不重复、余额正确、endDate 停用）。
void main() {
  setUpAll(setupSqlite3ForTests);

  late AppDatabase db;
  late RecurringRepositoryImpl repo;
  late int a;
  late int catA;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = RecurringRepositoryImpl(db.recurringDao, db.transactionDao);
    a = await db.accountDao.createAccount(
      AccountsCompanion.insert(
        name: '银行卡',
        type: AccountType.bank,
        balanceMinor: const Value(100000),
      ),
    );
    catA = await db.categoryDao.createCategory(
      CategoriesCompanion.insert(name: '居住', kind: CategoryKind.expense),
    );
  });

  tearDown(() async {
    await db.close();
  });

  test('月度规则连漏三期只生成三期，重复执行不重复生成', () async {
    final ruleId = await repo.addRule(
      name: '房租',
      type: TxnType.expense,
      accountId: a,
      categoryId: catA,
      amountMinor: 1000,
      frequency: RecurFrequency.monthly,
      startDate: DateTime(2026, 7, 10),
    );

    final now = DateTime(2026, 10, 5, 12);
    final generated = await repo.catchUp(now);
    expect(generated, 3); // 7-10、8-10、9-10

    // 余额扣减正确。
    final acc = await db.accountDao.getById(a);
    expect(acc!.balanceMinor, 100000 - 3000);

    // 规则推进到下一期。
    final rule = await db.recurringDao.getById(ruleId);
    expect(rule!.nextRunAt, DateTime(2026, 10, 10));
    expect(rule.active, isTrue);

    // 幂等：同一 now 再跑一次为 0。
    expect(await repo.catchUp(now), 0);

    // 每笔交易落在正确的发生日期。
    final txns = await db.transactionDao
        .watchByFilter(
          TxnFilter(start: DateTime(2026, 7), end: DateTime(2026, 11)),
        )
        .first;
    expect(txns.map((t) => t.occurredAt.day), everyElement(10));
    expect(txns.map((t) => t.occurredAt.month).toSet(), {7, 8, 9});
  });

  test('周规则与间隔：每 2 周一次', () async {
    await repo.addRule(
      name: '健身',
      type: TxnType.expense,
      accountId: a,
      amountMinor: 500,
      frequency: RecurFrequency.weekly,
      interval: 2,
      startDate: DateTime(2026, 10, 1),
    );
    final generated = await repo.catchUp(DateTime(2026, 10, 29));
    expect(generated, 3); // 10-01、10-15、10-29（29 <= until 含当天）
  });

  test('越过 endDate 自动停用，不再生成', () async {
    final ruleId = await repo.addRule(
      name: '会员',
      type: TxnType.expense,
      accountId: a,
      amountMinor: 1500,
      frequency: RecurFrequency.monthly,
      startDate: DateTime(2026, 1, 1),
      endDate: DateTime(2026, 2, 15),
    );
    final generated = await repo.catchUp(DateTime(2026, 12, 31));
    expect(generated, 2); // 1-1、2-1
    final rule = await db.recurringDao.getById(ruleId);
    expect(rule!.active, isFalse);
    // 停用后再跑不再生成。
    expect(await repo.catchUp(DateTime(2026, 12, 31)), 0);
  });

  test('收入规则生成收入并加余额', () async {
    await repo.addRule(
      name: '兼职工资',
      type: TxnType.income,
      accountId: a,
      amountMinor: 2000,
      frequency: RecurFrequency.monthly,
      startDate: DateTime(2026, 8, 5),
    );
    expect(await repo.catchUp(DateTime(2026, 10, 1)), 2); // 8-5、9-5
    final acc = await db.accountDao.getById(a);
    expect(acc!.balanceMinor, 100000 + 4000);
  });

  test('未到期规则不生成', () async {
    await repo.addRule(
      name: '未来账单',
      type: TxnType.expense,
      accountId: a,
      amountMinor: 100,
      frequency: RecurFrequency.monthly,
      startDate: DateTime(2026, 11, 1),
    );
    expect(await repo.catchUp(DateTime(2026, 10, 5)), 0);
    final acc = await db.accountDao.getById(a);
    expect(acc!.balanceMinor, 100000);
  });
}
