import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worthtrack/data/dao/transaction_dao.dart';
import 'package:worthtrack/data/db/app_database.dart';

import '../helpers/sqlite3_loader.dart';

/// issue #5 验收：余额计算（实时汇总）单测。
void main() {
  setUpAll(setupSqlite3ForTests);

  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> createAccount(
    String name, {
    AccountType type = AccountType.cash,
    int initialBalanceMinor = 0,
  }) {
    return db.accountDao.createAccount(
      AccountsCompanion.insert(
        name: name,
        type: type,
        balanceMinor: Value(initialBalanceMinor),
      ),
    );
  }

  group('余额实时计算', () {
    test('新建账户带初始余额', () async {
      final id = await createAccount('现金钱包', initialBalanceMinor: 12345);
      final acc = await db.accountDao.getById(id);
      expect(acc!.balanceMinor, 12345);
    });

    test('watchTotalBalanceMinor 汇总未归档账户', () async {
      await createAccount('a', initialBalanceMinor: 10000);
      await createAccount('b', initialBalanceMinor: 5000);
      await createAccount('c', initialBalanceMinor: 2500);

      expect(await db.accountDao.watchTotalBalanceMinor().first, 17500);

      // 归档 c 后总资产实时减少。
      await db.accountDao.archiveAccount(3);
      expect(await db.accountDao.watchTotalBalanceMinor().first, 15000);
    });

    test('watchBalanceByType 按类型汇总', () async {
      await createAccount(
        '现金1',
        type: AccountType.cash,
        initialBalanceMinor: 1000,
      );
      await createAccount(
        '现金2',
        type: AccountType.cash,
        initialBalanceMinor: 200,
      );
      await createAccount(
        '银行卡',
        type: AccountType.bank,
        initialBalanceMinor: 90000,
      );
      await createAccount(
        '证券',
        type: AccountType.investment,
        initialBalanceMinor: 500000,
      );

      final byType = await db.accountDao.watchBalanceByType().first;
      expect(byType[AccountType.cash], 1200);
      expect(byType[AccountType.bank], 90000);
      expect(byType[AccountType.investment], 500000);
      expect(byType.containsKey(AccountType.credit), isFalse);
    });

    test('记账后余额与总资产实时更新（碰钱路径联动）', () async {
      final accId = await createAccount('主卡', initialBalanceMinor: 100000);
      await createAccount('备用', initialBalanceMinor: 0);

      // 初始总资产 1000.00 元。
      expect(await db.accountDao.watchTotalBalanceMinor().first, 100000);

      // 支出 25.80 元 → 余额与总资产同步减少。
      await db.transactionDao.createWithBalanceUpdate(
        NewTransaction(
          type: TxnType.expense,
          accountId: accId,
          amountMinor: 2580,
          occurredAt: DateTime(2026, 10, 25, 12),
        ),
      );
      final acc = await db.accountDao.getById(accId);
      expect(acc!.balanceMinor, 97420);
      expect(await db.accountDao.watchTotalBalanceMinor().first, 97420);

      // 转账 10.00 元到备用账户 → 总资产不变，分布变化。
      final spareId = 2;
      await db.transactionDao.createWithBalanceUpdate(
        NewTransaction(
          type: TxnType.transfer,
          accountId: accId,
          toAccountId: spareId,
          amountMinor: 1000,
          occurredAt: DateTime(2026, 10, 25, 13),
        ),
      );
      expect((await db.accountDao.getById(accId))!.balanceMinor, 96420);
      expect((await db.accountDao.getById(spareId))!.balanceMinor, 1000);
      expect(await db.accountDao.watchTotalBalanceMinor().first, 97420);
    });

    test('updateAccount 修改名称与备注', () async {
      final id = await createAccount('旧名');
      await db.accountDao.updateAccount(
        id,
        const AccountsCompanion(name: Value('新名'), note: Value('备注')),
      );
      final acc = await db.accountDao.getById(id);
      expect(acc!.name, '新名');
      expect(acc.note, '备注');
    });

    test('unarchiveAccount 恢复归档账户', () async {
      final id = await createAccount('待恢复');
      await db.accountDao.archiveAccount(id);
      expect((await db.accountDao.watchAccounts().first).length, 0);
      await db.accountDao.unarchiveAccount(id);
      final list = await db.accountDao.watchAccounts().first;
      expect(list.length, 1);
      expect(list.first.archivedAt, isNull);
    });
  });
}
