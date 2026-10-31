import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worthtrack/modules/finance/data/dao/transaction_dao.dart';
import 'package:worthtrack/data/db/app_database.dart';

import '../helpers/sqlite3_loader.dart';

/// issue #12 验收：关键词/类型/账户/分类/时间组合过滤单测。
void main() {
  setUpAll(setupSqlite3ForTests);

  late AppDatabase db;
  late int a; // 工资卡
  late int b; // 现金
  late int catDining;
  late int catShopping;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    a = await db.accountDao.createAccount(
      AccountsCompanion.insert(name: '工资卡', type: AccountType.bank),
    );
    b = await db.accountDao.createAccount(
      AccountsCompanion.insert(name: '现金', type: AccountType.cash),
    );
    catDining = await db.categoryDao.createCategory(
      CategoriesCompanion.insert(name: '餐饮', kind: CategoryKind.expense),
    );
    catShopping = await db.categoryDao.createCategory(
      CategoriesCompanion.insert(name: '购物', kind: CategoryKind.expense),
    );
    // 十月数据
    await _txn(
      db,
      TxnType.expense,
      a,
      amountMinor: 1000,
      categoryId: catDining,
      note: '午饭',
      at: DateTime(2026, 10, 5, 12),
    );
    await _txn(
      db,
      TxnType.expense,
      b,
      amountMinor: 2000,
      categoryId: catShopping,
      note: '打车回程',
      at: DateTime(2026, 10, 6, 12),
    );
    await _txn(
      db,
      TxnType.transfer,
      a,
      toAccountId: b,
      amountMinor: 30000,
      at: DateTime(2026, 10, 7, 12),
    );
    await _txn(
      db,
      TxnType.income,
      a,
      amountMinor: 500000,
      note: '十月工资',
      at: DateTime(2026, 10, 8, 12),
    );
    // 九月数据（区间外）
    await _txn(
      db,
      TxnType.expense,
      a,
      amountMinor: 500,
      categoryId: catDining,
      note: '晚饭',
      at: DateTime(2026, 9, 30, 12),
    );
  });

  tearDown(() async {
    await db.close();
  });

  TxnFilter october({
    TxnType? type,
    int? accountId,
    int? categoryId,
    String? keyword,
  }) => TxnFilter(
    start: DateTime(2026, 10),
    end: DateTime(2026, 11),
    type: type,
    accountId: accountId,
    categoryId: categoryId,
    keyword: keyword,
  );

  Future<List<Transaction>> run(TxnFilter f) =>
      db.transactionDao.watchByFilter(f).first;

  group('单一条件', () {
    test('关键词匹配备注', () async {
      final r = await run(october(keyword: '午饭'));
      expect(r, hasLength(1));
      expect(r.single.note, '午饭');
    });

    test('关键词匹配分类名', () async {
      final r = await run(october(keyword: '餐饮'));
      expect(r, hasLength(1)); // 十月仅一笔餐饮分类交易（九月那笔在区间外）
    });

    test('关键词匹配账户名', () async {
      final r = await run(october(keyword: '工资卡'));
      // 工资卡上的：午饭支出、转账（转出方）、工资收入
      expect(r, hasLength(3));
    });

    test('类型过滤', () async {
      expect(await run(october(type: TxnType.income)), hasLength(1));
      expect(await run(october(type: TxnType.expense)), hasLength(2));
      expect(await run(october(type: TxnType.transfer)), hasLength(1));
    });

    test('账户过滤含转账目标账户', () async {
      final fromA = await run(october(accountId: a));
      expect(fromA, hasLength(3)); // 支出/转出/收入
      final inclB = await run(october(accountId: b));
      expect(inclB, hasLength(2)); // 打车支出 + 转入
    });

    test('分类过滤', () async {
      final r = await run(october(categoryId: catDining));
      expect(r, hasLength(1));
    });

    test('时间左闭右开：不含边界外交易', () async {
      final narrow = await run(
        TxnFilter(start: DateTime(2026, 10, 5), end: DateTime(2026, 10, 7)),
      );
      expect(narrow, hasLength(2)); // 10-05、10-06；10-07 不含
      final edge = await run(
        TxnFilter(start: DateTime(2026, 10, 7), end: DateTime(2026, 10, 8)),
      );
      expect(edge, hasLength(1));
    });
  });

  group('组合条件', () {
    test('关键词 + 类型 + 账户', () async {
      final r = await run(
        october(keyword: '工资', type: TxnType.income, accountId: a),
      );
      expect(r, hasLength(1)); // 十月工资
    });

    test('账户 + 分类', () async {
      final r = await run(october(accountId: b, categoryId: catShopping));
      expect(r, hasLength(1));
    });

    test('组合无匹配返回空', () async {
      final r = await run(october(keyword: '不存在', type: TxnType.income));
      expect(r, isEmpty);
    });

    test('无过滤条件返回全部（含九月共 5 条；限定十月 4 条）', () async {
      expect(await run(const TxnFilter()), hasLength(5));
      expect(await run(october()), hasLength(4));
    });
  });
}

Future<void> _txn(
  AppDatabase db,
  TxnType type,
  int accountId, {
  int? toAccountId,
  int? categoryId,
  required int amountMinor,
  String? note,
  required DateTime at,
}) {
  return db.transactionDao.createWithBalanceUpdate(
    NewTransaction(
      type: type,
      accountId: accountId,
      toAccountId: toAccountId,
      categoryId: categoryId,
      amountMinor: amountMinor,
      note: note,
      occurredAt: at,
    ),
  );
}
