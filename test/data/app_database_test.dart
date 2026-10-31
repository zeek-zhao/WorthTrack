import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worthtrack/modules/finance/data/dao/transaction_dao.dart';
import 'package:worthtrack/data/db/app_database.dart';

import '../helpers/sqlite3_loader.dart';

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
  }) {
    return db.accountDao.createAccount(
      AccountsCompanion.insert(name: name, type: type),
    );
  }

  group('开库与迁移', () {
    test('schemaVersion 为 1', () {
      expect(db.schemaVersion, 1);
    });

    test('onCreate 创建全部七张表', () async {
      final allTables = db.allTables.map((t) => t.actualTableName).toSet();
      expect(
        allTables,
        containsAll([
          'accounts',
          'categories',
          'transactions',
          'budgets',
          'recurring_rules',
          'positions',
          'price_cache',
        ]),
      );
    });

    test('文件库：关闭后重开数据仍在（迁移正常）', () async {
      final dir = await Directory.systemTemp.createTemp('wt_db_test');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}${Platform.pathSeparator}wt.db';

      final first = AppDatabase(NativeDatabase(File(path)));
      final accId = await first.accountDao.createAccount(
        AccountsCompanion.insert(name: '现金', type: AccountType.cash),
      );
      await first.close();

      final reopened = AppDatabase(NativeDatabase(File(path)));
      final acc = await reopened.accountDao.getById(accId);
      expect(acc, isNotNull);
      expect(acc!.name, '现金');
      await reopened.close();
    });

    test('枚举列按 int 存取往返', () async {
      final id = await createAccount('信用卡', type: AccountType.credit);
      final acc = await db.accountDao.getById(id);
      expect(acc!.type, AccountType.credit);
    });
  });

  group('账户 DAO', () {
    test('创建后可查回全部字段', () async {
      final id = await db.accountDao.createAccount(
        AccountsCompanion.insert(
          name: '工资卡',
          type: AccountType.bank,
          balanceMinor: const Value(100000),
          note: const Value('主要储蓄'),
        ),
      );
      final acc = await db.accountDao.getById(id);
      expect(acc!.name, '工资卡');
      expect(acc.type, AccountType.bank);
      expect(acc.balanceMinor, 100000);
      expect(acc.archivedAt, isNull);
    });

    test('watchAccounts 流式推送新增', () async {
      final stream = db.accountDao.watchAccounts();
      expectLater(
        stream,
        emitsThrough(
          isA<List<Account>>().having(
            (l) => l.map((a) => a.name),
            'names',
            contains('钱包'),
          ),
        ),
      );
      await createAccount('钱包');
    });

    test('watchAccounts 默认过滤归档账户', () async {
      final id = await createAccount('将归档');
      await db.accountDao.archiveAccount(id);

      final active = await db.accountDao.watchAccounts().first;
      expect(active, isEmpty);

      final all = await db.accountDao
          .watchAccounts(includeArchived: true)
          .first;
      expect(all, hasLength(1));
    });
  });

  group('交易 DAO：碰钱路径', () {
    late int cashId;
    late int bankId;

    setUp(() async {
      cashId = await createAccount('现金');
      bankId = await createAccount('银行卡', type: AccountType.bank);
    });

    test('支出：余额减少', () async {
      await db.transactionDao.createWithBalanceUpdate(
        NewTransaction(
          type: TxnType.expense,
          accountId: cashId,
          amountMinor: 2500,
          occurredAt: DateTime(2026, 10, 25, 12),
        ),
      );
      final acc = (await db.accountDao.getById(cashId))!;
      expect(acc.balanceMinor, -2500); // 初始 0，支出后为负（未充值场景）
    });

    test('收入：余额增加', () async {
      await db.transactionDao.createWithBalanceUpdate(
        NewTransaction(
          type: TxnType.income,
          accountId: cashId,
          amountMinor: 100000,
          occurredAt: DateTime(2026, 10, 25, 12),
        ),
      );
      final acc = (await db.accountDao.getById(cashId))!;
      expect(acc.balanceMinor, 100000);
    });

    test('转账：转出减少、转入增加', () async {
      await db.transactionDao.createWithBalanceUpdate(
        NewTransaction(
          type: TxnType.income,
          accountId: cashId,
          amountMinor: 50000,
          occurredAt: DateTime(2026, 10, 25, 12),
        ),
      );
      await db.transactionDao.createWithBalanceUpdate(
        NewTransaction(
          type: TxnType.transfer,
          accountId: cashId,
          toAccountId: bankId,
          amountMinor: 30000,
          occurredAt: DateTime(2026, 10, 25, 13),
        ),
      );
      expect((await db.accountDao.getById(cashId))!.balanceMinor, 20000);
      expect((await db.accountDao.getById(bankId))!.balanceMinor, 30000);
    });

    test('transfer 缺 toAccountId 抛 ArgumentError 且不落库', () async {
      expect(
        () => db.transactionDao.createWithBalanceUpdate(
          NewTransaction(
            type: TxnType.transfer,
            accountId: cashId,
            amountMinor: 100,
            occurredAt: DateTime(2026, 10, 25),
          ),
        ),
        throwsArgumentError,
      );
      final txns = await db.select(db.transactions).get();
      expect(txns, isEmpty);
    });

    test('账户不存在抛 StateError 且事务回滚不落库', () async {
      expect(
        () => db.transactionDao.createWithBalanceUpdate(
          NewTransaction(
            type: TxnType.expense,
            accountId: 99999,
            amountMinor: 100,
            occurredAt: DateTime(2026, 10, 25),
          ),
        ),
        throwsStateError,
      );
      expect(await db.select(db.transactions).get(), isEmpty);
    });

    test('watchByMonth 只返回指定月份', () async {
      await db.transactionDao.createWithBalanceUpdate(
        NewTransaction(
          type: TxnType.expense,
          accountId: cashId,
          amountMinor: 100,
          occurredAt: DateTime(2026, 10, 1),
        ),
      );
      await db.transactionDao.createWithBalanceUpdate(
        NewTransaction(
          type: TxnType.expense,
          accountId: cashId,
          amountMinor: 200,
          occurredAt: DateTime(2026, 9, 30),
        ),
      );

      final october = await db.transactionDao
          .watchByMonth(DateTime(2026, 10))
          .first;
      expect(october, hasLength(1));
      expect(october.first.amountMinor, 100);

      final september = await db.transactionDao
          .watchByMonth(DateTime(2026, 9))
          .first;
      expect(september, hasLength(1));
      expect(september.first.amountMinor, 200);
    });

    test('watchRecent 倒序返回', () async {
      await db.transactionDao.createWithBalanceUpdate(
        NewTransaction(
          type: TxnType.expense,
          accountId: cashId,
          amountMinor: 1,
          occurredAt: DateTime(2026, 10, 1),
        ),
      );
      await db.transactionDao.createWithBalanceUpdate(
        NewTransaction(
          type: TxnType.income,
          accountId: cashId,
          amountMinor: 2,
          occurredAt: DateTime(2026, 10, 2),
        ),
      );
      final list = await db.transactionDao.watchRecent().first;
      expect(list.map((t) => t.amountMinor), [2, 1]);
    });
  });

  group('约束', () {
    test('持仓 (market, code) 唯一', () async {
      Future<void> insert() => db
          .into(db.positions)
          .insert(
            PositionsCompanion.insert(
              market: Market.sh,
              code: '600519',
              name: '贵州茅台',
              sharesCent: 100,
              costPriceMinor: 150000,
            ),
          );
      await insert();
      await expectLater(insert(), throwsA(anything));
    });

    test('预算 (category, month) 唯一', () async {
      final catId = await db
          .into(db.categories)
          .insert(
            CategoriesCompanion.insert(name: '餐饮', kind: CategoryKind.expense),
          );
      Future<void> insert() => db
          .into(db.budgets)
          .insert(
            BudgetsCompanion.insert(
              categoryId: catId,
              amountMinor: 200000,
              month: DateTime(2026, 10),
            ),
          );
      await insert();
      await expectLater(insert(), throwsA(anything));
    });

    test('价格缓存按 symbol 主键 upsert', () async {
      await db
          .into(db.priceCache)
          .insert(
            PriceCacheCompanion.insert(
              symbol: 'sh600519',
              priceMinor: 150000,
              updatedAt: DateTime(2026, 10, 25, 9, 30),
            ),
          );
      await db
          .into(db.priceCache)
          .insertOnConflictUpdate(
            PriceCacheCompanion.insert(
              symbol: 'sh600519',
              priceMinor: 151000,
              updatedAt: DateTime(2026, 10, 25, 15),
            ),
          );
      final rows = await db.select(db.priceCache).get();
      expect(rows, hasLength(1));
      expect(rows.first.priceMinor, 151000);
    });
  });
}
