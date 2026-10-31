import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:worthtrack/data/db/app_database.dart';

import '../helpers/sqlite3_loader.dart';

/// v1 → v2 迁移测试（issue #43，本项目第一次写 onUpgrade）。
///
/// 做法：用 `test/fixtures/schema_v1.sql`（从 schemaVersion=1 的真实库导出的 DDL）
/// 造一个真正的 v1 库，塞入各表数据，再让 AppDatabase 打开它触发升级，
/// 最后逐表比对——**不是**「升级没抛异常」就算过。
void main() {
  setUpAll(setupSqlite3ForTests);

  late Directory dir;
  late String path;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('wt_migration_test');
    path = '${dir.path}${Platform.pathSeparator}worthtrack.sqlite3';
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  /// 用夹具 DDL 造 v1 库并塞入跨表数据。
  void seedV1Database() {
    // 先剥掉 `--` 注释行：否则首个 CREATE TABLE 会和注释粘在一起被整段跳过。
    final ddl = File('test/fixtures/schema_v1.sql')
        .readAsStringSync()
        .split('\n')
        .where((line) => !line.trimLeft().startsWith('--'))
        .join('\n');
    final db = sqlite.sqlite3.open(path);
    try {
      for (final stmt in ddl.split(';')) {
        final sql = stmt.trim();
        if (sql.isEmpty) continue;
        db.execute(sql);
      }
      db.execute('PRAGMA user_version = 1');

      // 金额一律整数分；时间一律 epoch 秒（drift 的 dateTime 存储格式）。
      db.execute(
        "INSERT INTO accounts (id, name, type, balance_minor, note, sort_order, archived_at, created_at) "
        "VALUES (1, '工资卡', 1, 1234567, '主要储蓄', 0, NULL, 1700000000)",
      );
      db.execute(
        "INSERT INTO accounts (id, name, type, balance_minor, note, sort_order, archived_at, created_at) "
        "VALUES (2, '信用卡', 2, -50000, NULL, 1, NULL, 1700000001)",
      );
      db.execute(
        "INSERT INTO categories (id, name, kind, icon, sort_order, parent_id, archived_at) "
        "VALUES (1, '餐饮', 0, 'food', 0, NULL, NULL)",
      );
      db.execute(
        "INSERT INTO transactions (id, type, account_id, to_account_id, category_id, amount_minor, note, occurred_at, created_at) "
        "VALUES (1, 0, 1, NULL, 1, 2500, '午饭,含逗号', 1700000100, 1700000100)",
      );
      db.execute(
        "INSERT INTO budgets (id, category_id, amount_minor, month, created_at) "
        "VALUES (1, 1, 200000, 1696118400, 1700000000)",
      );
      db.execute(
        "INSERT INTO positions (id, market, code, name, shares_cent, cost_price_minor, archived_at, created_at) "
        "VALUES (1, 0, '600519', '贵州茅台', 15000, 150000, NULL, 1700000000)",
      );
      db.execute(
        "INSERT INTO price_cache (symbol, price_minor, updated_at) "
        "VALUES ('sh600519', 151000, 1700000200)",
      );
      db.execute(
        "INSERT INTO recurring_rules (id, name, type, account_id, category_id, amount_minor, frequency, interval, start_date, next_run_at, end_date, active, note) "
        "VALUES (1, '房租', 0, 1, NULL, 300000, 2, 1, 1696118400, 1700000000, NULL, 1, NULL)",
      );
    } finally {
      db.dispose();
    }
  }

  Future<AppDatabase> openAndForceUpgrade() async {
    final db = AppDatabase(NativeDatabase(File(path)));
    // 迁移是懒执行的：不查一次就不会触发 onUpgrade。
    await db.customSelect('select 1').get();
    return db;
  }

  /// 取库里的表结构快照，用于「升级后 vs 全新库」比对。
  Future<Map<String, String>> schemaOf(AppDatabase db) async {
    final rows = await db
        .customSelect(
          "select name, sql from sqlite_master "
          "where type='table' and name not like 'sqlite_%' order by name",
        )
        .get();
    return {
      for (final r in rows) r.data['name'] as String: r.data['sql'] as String,
    };
  }

  group('v1 → v2 迁移', () {
    test('schemaVersion 已升到 2', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      expect(db.schemaVersion, 2);
    });

    test('全新库 onCreate 建出 8 张表，含 module_state', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.customSelect('select 1').get();

      final tables = db.allTables.map((t) => t.actualTableName).toSet();
      expect(tables, hasLength(8));
      expect(tables, contains('module_state'));
    });

    test('v1 库升级后：七张老表数据逐项无损', () async {
      seedV1Database();
      final db = await openAndForceUpgrade();
      addTearDown(db.close);

      final accounts = await db.select(db.accounts).get();
      expect(accounts, hasLength(2));
      final bank = accounts.firstWhere((a) => a.name == '工资卡');
      expect(bank.balanceMinor, 1234567);
      expect(bank.type, AccountType.bank);
      expect(bank.note, '主要储蓄');
      expect(accounts.firstWhere((a) => a.name == '信用卡').balanceMinor, -50000);

      final txns = await db.select(db.transactions).get();
      expect(txns, hasLength(1));
      expect(txns.single.amountMinor, 2500);
      expect(txns.single.note, '午饭,含逗号');
      expect(txns.single.categoryId, 1);

      final cats = await db.select(db.categories).get();
      expect(cats.single.name, '餐饮');

      final budgets = await db.select(db.budgets).get();
      expect(budgets.single.amountMinor, 200000);

      final positions = await db.select(db.positions).get();
      expect(positions.single.code, '600519');
      expect(positions.single.sharesCent, 15000);

      final prices = await db.select(db.priceCache).get();
      expect(prices.single.priceMinor, 151000);

      final rules = await db.select(db.recurringRules).get();
      expect(rules.single.name, '房租');
      expect(rules.single.frequency, RecurFrequency.monthly);
      expect(rules.single.active, isTrue);
    });

    test('v1 库升级后 module_state 存在且为空（不预设任何模块状态）', () async {
      seedV1Database();
      final db = await openAndForceUpgrade();
      addTearDown(db.close);

      final states = await db.select(db.moduleStates).get();
      expect(states, isEmpty);

      // 表结构可用：能写能读能按主键冲突更新。
      await db
          .into(db.moduleStates)
          .insert(
            ModuleStatesCompanion.insert(
              moduleId: 'finance',
              enabled: const Value(true),
              sortOrder: const Value(10),
            ),
          );
      final row = await (db.select(
        db.moduleStates,
      )..where((t) => t.moduleId.equals('finance'))).getSingle();
      expect(row.enabled, isTrue);
      expect(row.sortOrder, 10);
      expect(row.firstEnabledAt, isNull);
    });

    test('升级后的表结构与全新 v2 库完全一致', () async {
      seedV1Database();
      final upgraded = await openAndForceUpgrade();
      final upgradedSchema = await schemaOf(upgraded);
      await upgraded.close();

      final fresh = AppDatabase(NativeDatabase.memory());
      await fresh.customSelect('select 1').get();
      final freshSchema = await schemaOf(fresh);
      await fresh.close();

      expect(upgradedSchema.keys.toList()..sort(), freshSchema.keys.toList());
      for (final name in freshSchema.keys) {
        expect(
          upgradedSchema[name],
          freshSchema[name],
          reason: '表 $name 的建表语句在升级库与全新库之间不一致',
        );
      }
    });

    test('升级后 user_version 被写成 2', () async {
      seedV1Database();
      final db = await openAndForceUpgrade();
      await db.close();

      final raw = sqlite.sqlite3.open(path);
      final version = raw.select('PRAGMA user_version').first.values.first;
      raw.dispose();
      expect(version, 2);
    });

    test('升级可重复打开：第二次打开不再触发迁移、数据不变', () async {
      seedV1Database();
      final first = await openAndForceUpgrade();
      await first.close();

      final second = await openAndForceUpgrade();
      final accounts = await second.select(second.accounts).get();
      expect(accounts, hasLength(2));
      await second.close();
    });
  });
}
