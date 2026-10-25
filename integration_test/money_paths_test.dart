import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:worthtrack/data/dao/transaction_dao.dart';
import 'package:worthtrack/data/db/app_database.dart';

import '../test/helpers/sqlite3_loader.dart';

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
      const AccountsCompanion.insert(
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
      const AccountsCompanion.insert(name: '零钱', type: AccountType.cash),
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
}
