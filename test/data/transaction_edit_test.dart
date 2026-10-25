import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worthtrack/data/dao/transaction_dao.dart';
import 'package:worthtrack/data/db/app_database.dart';

import '../helpers/sqlite3_loader.dart';

/// issue #6：交易编辑/删除的碰钱路径单测。
void main() {
  setUpAll(setupSqlite3ForTests);

  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> account(String name, {int balanceMinor = 0}) {
    return db.accountDao.createAccount(
      AccountsCompanion.insert(
        name: name,
        type: AccountType.cash,
        balanceMinor: Value(balanceMinor),
      ),
    );
  }

  NewTransaction txn(
    TxnType type,
    int accountId, {
    int? toAccountId,
    required int amountMinor,
  }) => NewTransaction(
    type: type,
    accountId: accountId,
    toAccountId: toAccountId,
    amountMinor: amountMinor,
    occurredAt: DateTime(2026, 10, 25, 12),
  );

  group('交易编辑（余额同步调整）', () {
    test('修改支出金额：余额按差额调整', () async {
      final a = await account('主卡', balanceMinor: 100000);
      final id = await db.transactionDao.createWithBalanceUpdate(
        txn(TxnType.expense, a, amountMinor: 2000),
      );
      expect((await db.accountDao.getById(a))!.balanceMinor, 98000);

      await db.transactionDao.updateWithBalanceAdjust(
        id,
        txn(TxnType.expense, a, amountMinor: 3500),
      );
      expect((await db.accountDao.getById(a))!.balanceMinor, 96500);
    });

    test('支出改收入：余额先冲销再应用', () async {
      final a = await account('主卡', balanceMinor: 100000);
      final id = await db.transactionDao.createWithBalanceUpdate(
        txn(TxnType.expense, a, amountMinor: 2000),
      );

      await db.transactionDao.updateWithBalanceAdjust(
        id,
        txn(TxnType.income, a, amountMinor: 5000),
      );
      // 100000 + 2000（冲销支出）+ 5000（收入）= 105000
      expect((await db.accountDao.getById(a))!.balanceMinor, 105000);
    });

    test('转账目标变更：旧目标回滚、新目标应用', () async {
      final a = await account('A', balanceMinor: 100000);
      final b = await account('B', balanceMinor: 0);
      final c = await account('C', balanceMinor: 0);
      final id = await db.transactionDao.createWithBalanceUpdate(
        txn(TxnType.transfer, a, toAccountId: b, amountMinor: 10000),
      );
      expect((await db.accountDao.getById(b))!.balanceMinor, 10000);

      await db.transactionDao.updateWithBalanceAdjust(
        id,
        txn(TxnType.transfer, a, toAccountId: c, amountMinor: 10000),
      );
      expect((await db.accountDao.getById(a))!.balanceMinor, 90000);
      expect((await db.accountDao.getById(b))!.balanceMinor, 0);
      expect((await db.accountDao.getById(c))!.balanceMinor, 10000);
    });

    test('编辑不存在的交易抛 StateError', () async {
      final a = await account('A');
      expect(
        () => db.transactionDao.updateWithBalanceAdjust(
          999,
          txn(TxnType.expense, a, amountMinor: 100),
        ),
        throwsStateError,
      );
    });
  });

  group('交易删除（余额回滚）', () {
    test('删除支出：余额恢复', () async {
      final a = await account('主卡', balanceMinor: 100000);
      final id = await db.transactionDao.createWithBalanceUpdate(
        txn(TxnType.expense, a, amountMinor: 2000),
      );
      expect((await db.accountDao.getById(a))!.balanceMinor, 98000);

      await db.transactionDao.deleteWithBalanceReversal(id);
      expect((await db.accountDao.getById(a))!.balanceMinor, 100000);
      expect(await (db.select(db.transactions)).get(), isEmpty);
    });

    test('删除转账：双方余额都回滚', () async {
      final a = await account('A', balanceMinor: 100000);
      final b = await account('B', balanceMinor: 0);
      final id = await db.transactionDao.createWithBalanceUpdate(
        txn(TxnType.transfer, a, toAccountId: b, amountMinor: 30000),
      );
      expect((await db.accountDao.getById(a))!.balanceMinor, 70000);
      expect((await db.accountDao.getById(b))!.balanceMinor, 30000);

      await db.transactionDao.deleteWithBalanceReversal(id);
      expect((await db.accountDao.getById(a))!.balanceMinor, 100000);
      expect((await db.accountDao.getById(b))!.balanceMinor, 0);
    });

    test('删除不存在的交易幂等不抛错', () async {
      await db.transactionDao.deleteWithBalanceReversal(999);
    });
  });

  group('月度筛选', () {
    test('watchByMonth 按账户与分类过滤', () async {
      final a = await account('A');
      final b = await account('B');
      final catId = await db.categoryDao.createCategory(
        CategoriesCompanion.insert(name: '餐饮', kind: CategoryKind.expense),
      );

      await db.transactionDao.createWithBalanceUpdate(
        NewTransaction(
          type: TxnType.expense,
          accountId: a,
          categoryId: catId,
          amountMinor: 1000,
          occurredAt: DateTime(2026, 10, 1),
        ),
      );
      await db.transactionDao.createWithBalanceUpdate(
        NewTransaction(
          type: TxnType.expense,
          accountId: b,
          amountMinor: 2000,
          occurredAt: DateTime(2026, 10, 2),
        ),
      );
      await db.transactionDao.createWithBalanceUpdate(
        NewTransaction(
          type: TxnType.expense,
          accountId: a,
          categoryId: catId,
          amountMinor: 3000,
          occurredAt: DateTime(2026, 9, 15), // 上月
        ),
      );

      final october = await db.transactionDao
          .watchByMonth(DateTime(2026, 10))
          .first;
      expect(october.length, 2);

      final byAccount = await db.transactionDao
          .watchByMonth(DateTime(2026, 10), accountId: a)
          .first;
      expect(byAccount.length, 1);
      expect(byAccount.first.amountMinor, 1000);

      final byCategory = await db.transactionDao
          .watchByMonth(DateTime(2026, 10), categoryId: catId)
          .first;
      expect(byCategory.length, 1);
      expect(byCategory.first.amountMinor, 1000);
    });
  });
}
