import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:worthtrack/core/backup/database_backup_repository.dart';
import 'package:worthtrack/modules/finance/data/dao/transaction_dao.dart';
import 'package:worthtrack/data/db/app_database.dart';
import 'package:worthtrack/core/backup/backup.dart';

import '../helpers/sqlite3_loader.dart';

/// issue #18 验收：导出 → 清空 → 恢复后数据一致（真 Drift + 真 SQLite 文件）。
void main() {
  setUpAll(() {
    setupSqlite3ForTests();
    // 本文件会同时开两个 AppDatabase（模拟「另一台手机」/「造一份坏备份」），
    // 用的是各自的文件或内存库，不存在共用连接，关掉这条误导性告警。
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  late AppDatabase db;
  late Directory tempDir;
  late DatabaseBackupRepository repo;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    tempDir = await Directory.systemTemp.createTemp('wt_backup_test_');
    repo = DatabaseBackupRepository(db, tempDirectory: () async => tempDir);
  });

  tearDown(() async {
    await db.close();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  /// 造一份有代表性的账本：账户 + 分类 + 收支 + 预算 + 周期规则 + 持仓 + 行情。
  Future<void> seed() async {
    final bank = await db.accountDao.createAccount(
      AccountsCompanion.insert(
        name: '工资卡',
        type: AccountType.bank,
        balanceMinor: const Value(1000000), // ¥10000.00
      ),
    );
    final cash = await db.accountDao.createAccount(
      AccountsCompanion.insert(name: '零钱', type: AccountType.cash),
    );
    final food = await db.categoryDao.createCategory(
      CategoriesCompanion.insert(name: '餐饮', kind: CategoryKind.expense),
    );
    await db.transactionDao.createWithBalanceUpdate(
      NewTransaction(
        type: TxnType.expense,
        accountId: bank,
        categoryId: food,
        amountMinor: 2580, // ¥25.80
        note: '午饭',
        occurredAt: DateTime(2026, 10, 20, 12),
      ),
    );
    await db.transactionDao.createWithBalanceUpdate(
      NewTransaction(
        type: TxnType.transfer,
        accountId: bank,
        toAccountId: cash,
        amountMinor: 100000, // ¥1000.00
        occurredAt: DateTime(2026, 10, 21, 9),
      ),
    );
    await db.budgetDao.upsert(
      DateTime(2026, 10),
      categoryId: food,
      amountMinor: 150000,
    );
    await db.recurringDao.createRule(
      RecurringRulesCompanion.insert(
        name: '房租',
        type: TxnType.expense,
        accountId: bank,
        amountMinor: 150000,
        frequency: RecurFrequency.monthly,
        startDate: DateTime(2026, 10, 10),
        nextRunAt: DateTime(2026, 11, 10),
      ),
    );
    await db.positionDao.createPosition(
      PositionsCompanion.insert(
        market: Market.sh,
        code: '600519',
        name: '贵州茅台',
        sharesCent: 15000, // 150.00 份
        costPriceMinor: 160000,
      ),
    );
    await db.positionDao.upsertPrice(
      'sh600519',
      135590,
      at: DateTime(2026, 10, 27, 16, 14),
    );
  }

  /// 把导出的字节落成文件，返回路径（模拟用户选的保存位置）。
  Future<String> writeBackup(Uint8List bytes) async {
    final file = File('${tempDir.path}/backup.sqlite3');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// 账本关键事实快照：任何一项变化都说明恢复没做到「数据一致」。
  Future<List<Object?>> snapshot(AppDatabase target) async {
    final accounts = await target.select(target.accounts).get();
    final txns = await target.transactionDao
        .watchByMonth(DateTime(2026, 10))
        .first;
    final budgets = await target.select(target.budgets).get();
    final rules = await target.select(target.recurringRules).get();
    final positions = await target.select(target.positions).get();
    final price = await target.positionDao.getPrice('sh600519');
    return [
      for (final a in accounts) '${a.id}/${a.name}/${a.balanceMinor}',
      for (final t in txns) '${t.id}/${t.type}/${t.amountMinor}/${t.note}',
      for (final b in budgets) '${b.categoryId}/${b.amountMinor}',
      for (final r in rules) '${r.name}/${r.nextRunAt}',
      for (final p in positions)
        '${p.code}/${p.sharesCent}/${p.costPriceMinor}',
      if (price != null) '${price.priceMinor}@${price.updatedAt}',
    ];
  }

  test('导出 → 清空 → 恢复：数据逐项一致，且能继续记账', () async {
    await seed();
    final before = await snapshot(db);

    final bytes = await repo.exportBytes();
    expect(hasSqliteHeader(bytes), isTrue, reason: '导出物必须是 SQLite 文件');
    final path = await writeBackup(bytes);

    // 导出用的临时文件不能留在用户设备上。
    expect(
      tempDir.listSync().where((e) => e.path.contains('worthtrack-export-')),
      isEmpty,
    );

    // 清空（等价于用户误删 / 换机前的空库）。
    for (final table in [
      'transactions',
      'budgets',
      'recurring_rules',
      'positions',
      'price_cache',
      'categories',
      'accounts',
    ]) {
      await db.customStatement('DELETE FROM "$table"');
    }
    expect(await snapshot(db), isEmpty);

    final inspection = await repo.inspect(path);
    expect(inspection.problem, isNull);
    expect(inspection.schemaVersion, 2);
    expect(inspection.accountCount, 2);
    expect(inspection.transactionCount, 2);
    expect(inspection.positionCount, 1);
    expect(inspection.fileName, 'backup.sqlite3');

    await repo.restoreFrom(path);
    expect(await snapshot(db), before);

    // 恢复后自增 id 不能倒退撞车：再记一笔要能正常插入。
    final accountId = (await db.select(db.accounts).get()).first.id;
    await db.transactionDao.createWithBalanceUpdate(
      NewTransaction(
        type: TxnType.expense,
        accountId: accountId,
        amountMinor: 100,
        occurredAt: DateTime(2026, 10, 28, 8),
      ),
    );
    final txns = await db.transactionDao.watchByMonth(DateTime(2026, 10)).first;
    expect(txns, hasLength(3));
    expect(txns.map((t) => t.id).toSet(), hasLength(3));
  });

  test('恢复到一台「新手机」的空库：备份可以跨设备迁移', () async {
    await seed();
    final before = await snapshot(db);
    final path = await writeBackup(await repo.exportBytes());

    final fresh = AppDatabase(NativeDatabase.memory());
    addTearDown(fresh.close);
    final freshRepo = DatabaseBackupRepository(
      fresh,
      tempDirectory: () async => tempDir,
    );

    final inspection = await freshRepo.inspect(path);
    expect(inspection.canRestore, isTrue);
    await freshRepo.restoreFrom(path);

    expect(await snapshot(fresh), before);
  });

  test('空文件 / 文本文件 / 别的 sqlite 库都被挡在恢复之前', () async {
    await seed();
    final before = await snapshot(db);

    final empty = File('${tempDir.path}/empty.sqlite3');
    await empty.writeAsBytes(const []);
    expect((await repo.inspect(empty.path)).problem, BackupProblem.empty);

    final text = File('${tempDir.path}/notes.txt');
    await text.writeAsString('这不是数据库');
    expect((await repo.inspect(text.path)).problem, BackupProblem.notSqlite);

    // 一个合法的 SQLite 库，但表不是我们那七张。
    // 注意不能用 AppDatabase 打开它——drift 会按 onCreate 把七张表建出来。
    final alienPath = '${tempDir.path}/alien.sqlite3';
    await db.customStatement('ATTACH DATABASE ? AS alien', [alienPath]);
    await db.customStatement('CREATE TABLE alien.foo (id INTEGER PRIMARY KEY)');
    await db.customStatement('DETACH DATABASE alien');
    expect(
      (await repo.inspect(alienPath)).problem,
      BackupProblem.missingTables,
    );

    // 三种都不允许走到「覆盖数据」那一步。
    for (final bad in [empty.path, text.path, alienPath]) {
      await expectLater(repo.restoreFrom(bad), throwsA(isA<BackupException>()));
    }
    expect(await snapshot(db), before);
  });

  test('备份来自更高版本 → 提示先升级应用', () async {
    await seed();
    final path = await writeBackup(await repo.exportBytes());

    // 手工把备份文件的 user_version 抬到 99，模拟「新版应用导出的备份」。
    await db.customStatement('ATTACH DATABASE ? AS bump', [path]);
    await db.customStatement('PRAGMA bump.user_version = 99');
    await db.customStatement('DETACH DATABASE bump');

    final inspection = await repo.inspect(path);
    expect(inspection.problem, BackupProblem.schemaNewer);
    expect(inspection.schemaVersion, 99);
    await expectLater(
      repo.restoreFrom(path),
      throwsA(
        isA<BackupException>().having(
          (e) => e.problem,
          'problem',
          BackupProblem.schemaNewer,
        ),
      ),
    );
  });

  test('恢复中途失败 → 整体回滚，原数据一条不少', () async {
    await seed();
    final before = await snapshot(db);
    final path = await writeBackup(await repo.exportBytes());

    // 制造一份「表齐、版本对，但结构不一致」的备份：
    // 少一列 → 逐表 INSERT ... SELECT * 会在中途炸掉。
    final broken = AppDatabase(NativeDatabase(File(path)));
    await broken.customStatement('ALTER TABLE transactions DROP COLUMN note');
    await broken.close();

    expect((await repo.inspect(path)).canRestore, isTrue, reason: '表与版本都过关');

    await expectLater(
      repo.restoreFrom(path),
      throwsA(
        isA<BackupException>().having(
          (e) => e.problem,
          'problem',
          BackupProblem.restoreFailed,
        ),
      ),
    );
    // 关键断言：事务回滚后账本与恢复前一模一样（不是「清空了但没写回来」）。
    expect(await snapshot(db), before);
  });

  test('拿应用正在用的库文件自己恢复 → 直接拒绝', () async {
    final livePath = '${tempDir.path}/live.sqlite3';
    final live = AppDatabase(NativeDatabase(File(livePath)));
    addTearDown(live.close);
    await live.accountDao.createAccount(
      AccountsCompanion.insert(
        name: '工资卡',
        type: AccountType.bank,
        balanceMinor: const Value(500000),
      ),
    );
    final liveRepo = DatabaseBackupRepository(
      live,
      tempDirectory: () async => tempDir,
    );

    await expectLater(
      liveRepo.restoreFrom(livePath),
      throwsA(
        isA<BackupException>().having(
          (e) => e.problem,
          'problem',
          BackupProblem.sameDatabase,
        ),
      ),
    );
    expect(await live.accountDao.watchTotalBalanceMinor().first, 500000);
  });

  test('恢复会替换而不追加：重复恢复同一份备份结果不变（幂等）', () async {
    await seed();
    final path = await writeBackup(await repo.exportBytes());
    final before = await snapshot(db);

    await repo.restoreFrom(path);
    await repo.restoreFrom(path);

    expect(await snapshot(db), before);
  });

  group('module_state 随备份走（#43）', () {
    test('v2 备份往返后模块开关与排序一致', () async {
      await seed();
      await db
          .into(db.moduleStates)
          .insert(
            ModuleStatesCompanion.insert(
              moduleId: 'finance',
              enabled: const Value(false),
              sortOrder: const Value(7),
              firstEnabledAt: Value(DateTime(2026, 10, 1, 9)),
            ),
          );

      final path = await writeBackup(await repo.exportBytes());
      await db.customStatement('DELETE FROM "module_state"');
      expect(await db.select(db.moduleStates).get(), isEmpty);

      await repo.restoreFrom(path);

      final rows = await db.select(db.moduleStates).get();
      expect(rows, hasLength(1));
      expect(rows.single.moduleId, 'finance');
      expect(rows.single.enabled, isFalse);
      expect(rows.single.sortOrder, 7);
      expect(rows.single.firstEnabledAt, DateTime(2026, 10, 1, 9));
    });

    test('恢复 v1 备份（没有 module_state 表）：账本替换、模块开关保持', () async {
      await seed();
      await db
          .into(db.moduleStates)
          .insert(
            ModuleStatesCompanion.insert(
              moduleId: 'finance',
              enabled: const Value(true),
              sortOrder: const Value(3),
            ),
          );

      // 用 v1 的真实 DDL 造一份旧备份：只有 7 张表、user_version = 1。
      final v1Path =
          '${tempDir.path}${Platform.pathSeparator}v1-backup.sqlite3';
      final raw = sqlite.sqlite3.open(v1Path);
      final ddl = File('test/fixtures/schema_v1.sql')
          .readAsStringSync()
          .split('\n')
          .where((line) => !line.trimLeft().startsWith('--'))
          .join('\n');
      for (final stmt in ddl.split(';')) {
        final sql = stmt.trim();
        if (sql.isEmpty) continue;
        raw.execute(sql);
      }
      raw.execute('PRAGMA user_version = 1');
      raw.execute(
        "INSERT INTO accounts (id, name, type, balance_minor, note, sort_order, archived_at, created_at) "
        "VALUES (1, '旧手机的钱包', 0, 8888, NULL, 0, NULL, 1700000000)",
      );
      raw.dispose();

      // 旧版本备份现在允许恢复（#60）。
      final inspection = await repo.inspect(v1Path);
      expect(inspection.problem, isNull);
      expect(inspection.schemaVersion, 1);
      expect(inspection.accountCount, 1);

      await repo.restoreFrom(v1Path);

      // 账本被旧备份替换……
      final accounts = await db.select(db.accounts).get();
      expect(accounts.single.name, '旧手机的钱包');
      expect(accounts.single.balanceMinor, 8888);
      // ……但模块开关保持原样（v1 备份里没有这个信息，不该被抹掉）。
      final states = await db.select(db.moduleStates).get();
      expect(states.single.moduleId, 'finance');
      expect(states.single.enabled, isTrue);
      expect(states.single.sortOrder, 3);
    });
  });
}
