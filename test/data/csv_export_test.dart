import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worthtrack/modules/finance/data/dao/transaction_dao.dart';
import 'package:worthtrack/data/db/app_database.dart';
import 'package:worthtrack/modules/finance/data/repositories/export_repository_impl.dart';
import 'package:worthtrack/modules/finance/domain/csv_export.dart';

import '../helpers/sqlite3_loader.dart';

/// issue #19 验收：CSV 字段正确、UTF-8 BOM、中文与逗号转义（真 Drift）。
void main() {
  setUpAll(setupSqlite3ForTests);

  late AppDatabase db;
  late ExportRepositoryImpl repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = ExportRepositoryImpl(
      db.transactionDao,
      now: () => DateTime(2026, 10, 28, 22, 45),
    );
  });

  tearDown(() async {
    await db.close();
  });

  /// 去掉 BOM 后按 UTF-8 解码，模拟 Excel 的行为。
  String decode(CsvExport export) =>
      utf8.decode(export.bytes.sublist(csvUtf8Bom.length));

  Future<int> addAccount(String name, {int balanceMinor = 0}) {
    return db.accountDao.createAccount(
      AccountsCompanion.insert(
        name: name,
        type: AccountType.bank,
        balanceMinor: Value(balanceMinor),
      ),
    );
  }

  test('导出全部流水：列顺序、账户/分类名称、金额与时间都正确', () async {
    final bank = await addAccount('工资卡', balanceMinor: 1000000);
    final cash = await addAccount('零钱');
    final food = await db.categoryDao.createCategory(
      CategoriesCompanion.insert(name: '餐饮', kind: CategoryKind.expense),
    );
    final salary = await db.categoryDao.createCategory(
      CategoriesCompanion.insert(name: '工资', kind: CategoryKind.income),
    );

    await db.transactionDao.createWithBalanceUpdate(
      NewTransaction(
        type: TxnType.expense,
        accountId: bank,
        categoryId: food,
        amountMinor: 2580,
        note: '午饭',
        occurredAt: DateTime(2026, 10, 20, 12, 30),
      ),
    );
    await db.transactionDao.createWithBalanceUpdate(
      NewTransaction(
        type: TxnType.income,
        accountId: bank,
        categoryId: salary,
        amountMinor: 1000000,
        occurredAt: DateTime(2026, 10, 1, 9),
      ),
    );
    await db.transactionDao.createWithBalanceUpdate(
      NewTransaction(
        type: TxnType.transfer,
        accountId: bank,
        toAccountId: cash,
        amountMinor: 50000,
        note: '取现',
        occurredAt: DateTime(2026, 10, 21, 8, 5),
      ),
    );

    final export = await repo.transactionsCsv();
    expect(export.rowCount, 3);
    expect(export.generatedAt, DateTime(2026, 10, 28, 22, 45));
    expect(export.bytes.sublist(0, 3), csvUtf8Bom);

    final lines = decode(export).split('\r\n');
    expect(lines.first, '时间,类型,账户,分类,金额,备注');
    // 时间正序：10-01 → 10-20 → 10-21
    expect(lines[1], '2026-10-01 09:00,收入,工资卡,工资,10000.00,');
    expect(lines[2], '2026-10-20 12:30,支出,工资卡,餐饮,25.80,午饭');
    expect(lines[3], '2026-10-21 08:05,转账,工资卡 → 零钱,,500.00,取现');
  });

  test('备注里的逗号与引号不会把列拆散', () async {
    final accountId = await addAccount('现金');
    await db.transactionDao.createWithBalanceUpdate(
      NewTransaction(
        type: TxnType.expense,
        accountId: accountId,
        amountMinor: 100,
        note: '午饭,"加饮料"',
        occurredAt: DateTime(2026, 10, 20, 12),
      ),
    );

    final lines = decode(await repo.transactionsCsv()).split('\r\n');
    expect(lines, hasLength(3)); // 表头 + 1 行 + 末尾空串
    expect(lines[1], '2026-10-20 12:00,支出,现金,,1.00,"午饭,""加饮料"""');
  });

  test('空账本导出的是一份只有表头的合法 CSV', () async {
    final export = await repo.transactionsCsv();
    expect(export.rowCount, 0);
    expect(decode(export), '时间,类型,账户,分类,金额,备注\r\n');
  });

  test('归档账户的流水照样导出（归档不等于删除）', () async {
    final accountId = await addAccount('旧卡');
    await db.transactionDao.createWithBalanceUpdate(
      NewTransaction(
        type: TxnType.expense,
        accountId: accountId,
        amountMinor: 500,
        occurredAt: DateTime(2026, 10, 2, 10),
      ),
    );
    await db.accountDao.archiveAccount(accountId);

    final export = await repo.transactionsCsv();
    expect(export.rowCount, 1);
    expect(decode(export), contains('旧卡'));
  });
}
