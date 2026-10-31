import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worthtrack/core/module/app_module.dart';
import 'package:worthtrack/core/module/module_data_cleaner.dart';
import 'package:worthtrack/data/db/app_database.dart';
import 'package:worthtrack/modules/finance/finance_module.dart';

import '../helpers/sqlite3_loader.dart';

/// 一个「只拥有 accounts」的假模块，用来验证清理**不会越界**。
class _AccountsOnlyModule extends AppModule {
  const _AccountsOnlyModule();

  @override
  ModuleId get id => 'accounts-only';

  @override
  String get name => '只有账户';

  @override
  IconData get icon => Icons.account_balance;

  @override
  int get defaultOrder => 99;

  @override
  Set<String> get ownedTables => const {'accounts'};

  @override
  Map<String, String> get tableLabels => const {'accounts': '账户'};
}

/// issue #45：模块数据的计数与清理。
///
/// 两条不变量必须由测试钉住：
/// 1. **只删 `ownedTables`**，不波及别人；
/// 2. 删除是**物理**的（停用不动数据，清理才动）。
void main() {
  setUpAll(setupSqlite3ForTests);

  late AppDatabase db;
  late ModuleDataCleaner cleaner;
  const finance = FinanceModule();

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    cleaner = ModuleDataCleaner(db);
  });

  tearDown(() async {
    await db.close();
  });

  /// 塞入一组跨表数据：账户 / 分类 / 流水 / 持仓 / 预算。
  Future<void> seed() async {
    await db
        .into(db.accounts)
        .insert(AccountsCompanion.insert(name: '工资卡', type: AccountType.bank));
    await db
        .into(db.accounts)
        .insert(
          AccountsCompanion.insert(name: '信用卡', type: AccountType.credit),
        );
    await db
        .into(db.categories)
        .insert(
          CategoriesCompanion.insert(name: '餐饮', kind: CategoryKind.expense),
        );
    await db
        .into(db.transactions)
        .insert(
          TransactionsCompanion.insert(
            type: TxnType.expense,
            accountId: 1,
            amountMinor: 2350,
            occurredAt: DateTime(2025, 5, 1, 12),
          ),
        );
    await db
        .into(db.positions)
        .insert(
          PositionsCompanion.insert(
            market: Market.sh,
            code: '600519',
            name: '贵州茅台',
            sharesCent: 10000,
            costPriceMinor: 150000,
          ),
        );
    await db
        .into(db.budgets)
        .insert(
          BudgetsCompanion.insert(
            categoryId: 1,
            amountMinor: 100000,
            month: DateTime(2025, 5),
          ),
        );
    // 模块开关属于 core，清理 finance 时**不能**被动到。
    await db
        .into(db.moduleStates)
        .insert(
          ModuleStatesCompanion.insert(
            moduleId: 'finance',
            enabled: const Value(true),
          ),
        );
  }

  ModuleContext ctx() =>
      ModuleContext(database: db, logger: const DebugModuleLogger());

  group('countRows', () {
    test('按表统计条数', () async {
      await seed();
      final counts = await cleaner.countRows(finance.ownedTables);
      expect(counts['accounts'], 2);
      expect(counts['transactions'], 1);
      expect(counts['positions'], 1);
      expect(counts['budgets'], 1);
      expect(counts['price_cache'], 0);
    });

    test('不存在的表被跳过，不抛异常', () async {
      final counts = await cleaner.countRows({'accounts', 'no_such_table'});
      expect(counts.keys, ['accounts']);
    });

    test('totalRows 只算自己的表', () async {
      await seed();
      expect(await cleaner.totalRows(finance), 6);
      expect(await cleaner.totalRows(const _AccountsOnlyModule()), 2);
    });
  });

  group('clearModule', () {
    test('清空 finance 的全部业务表，返回删除条数', () async {
      await seed();
      final removed = await cleaner.clearModule(finance, ctx());

      expect(removed, 6);
      expect(await db.select(db.accounts).get(), isEmpty);
      expect(await db.select(db.transactions).get(), isEmpty);
      expect(await db.select(db.categories).get(), isEmpty);
      expect(await db.select(db.positions).get(), isEmpty);
      expect(await db.select(db.budgets).get(), isEmpty);
    });

    test('**不碰 module_state**：清理数据 ≠ 重置模块开关', () async {
      await seed();
      await cleaner.clearModule(finance, ctx());

      final states = await db.select(db.moduleStates).get();
      expect(states, hasLength(1));
      expect(states.single.moduleId, 'finance');
      expect(states.single.enabled, isTrue);
    });

    test('只删自己声明的表：别的模块的表一行不动', () async {
      await seed();
      // 假设 accounts 归别人，finance 之外的模块来清理账户表。
      await cleaner.clearModule(const _AccountsOnlyModule(), ctx());

      expect(await db.select(db.accounts).get(), isEmpty);
      // 别人的数据必须还在。
      expect(await db.select(db.transactions).get(), hasLength(1));
      expect(await db.select(db.categories).get(), hasLength(1));
      expect(await db.select(db.positions).get(), hasLength(1));
      expect(await db.select(db.budgets).get(), hasLength(1));
    });

    test('外键有依赖也能一次删干净（defer_foreign_keys）', () async {
      await seed();
      // transactions → accounts / categories，categories 自引用；顺序错了会报错。
      await expectLater(cleaner.clearModule(finance, ctx()), completes);
    });

    test('空库清理返回 0，不报错', () async {
      expect(await cleaner.clearModule(finance, ctx()), 0);
    });

    test('清理后调用模块 onClear 钩子（收尾）', () async {
      final module = _SpyModule();
      await cleaner.clearModule(module, ctx());
      expect(module.clearCalls, 1);
    });
  });

  group('describeRowCounts', () {
    test('按总数 + 分表拼一句中文', () {
      expect(
        describeRowCounts(
          {'accounts': 3, 'transactions': 120, 'categories': 14},
          labels: const {'accounts': '账户', 'transactions': '流水'},
        ),
        '共 137 条（账户 3 · 流水 120 · categories 14）',
      );
    });

    test('没有数据时给一句人话', () {
      expect(describeRowCounts(const {'accounts': 0}), '暂无数据');
      expect(describeRowCounts(const {}), '暂无数据');
    });

    test('没有中文标签的表直接显示表名，不猜', () {
      expect(
        describeRowCounts(const {'price_cache': 2}),
        '共 2 条（price_cache 2）',
      );
    });
  });
}

class _SpyModule extends AppModule {
  int clearCalls = 0;

  @override
  ModuleId get id => 'spy';

  @override
  String get name => '探针';

  @override
  IconData get icon => Icons.science;

  @override
  int get defaultOrder => 98;

  @override
  Set<String> get ownedTables => const {'price_cache'};

  @override
  Future<void> onClear(ModuleContext context) async {
    clearCalls++;
  }
}
