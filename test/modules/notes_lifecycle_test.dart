import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worthtrack/core/module/app_module.dart';
import 'package:worthtrack/core/module/module_data_cleaner.dart';
import 'package:worthtrack/core/module/module_registry.dart';
import 'package:worthtrack/core/module/module_state_repository.dart';
import 'package:worthtrack/core/router.dart';
import 'package:worthtrack/data/db/app_database.dart';
import 'package:worthtrack/modules/finance/finance_module.dart';
import 'package:worthtrack/modules/notes/notes_module.dart';

import '../helpers/sqlite3_loader.dart';

/// issue #50：模块停用 / 清理对 notes 数据的正确性。
///
/// 这是 M6 的收口测试，钉住三条容易在重构里被悄悄破坏的承诺：
///
/// 1. **停用 ≠ 删除**：停用只改开关，数据一行不动；
/// 2. **清理只删自己的表**：删 notes 时 finance 的七张表一条不少，反之亦然；
/// 3. **弱引用不会因为对方消失而失效**：标的被删了，挂在它上面的笔记还在。
void main() {
  setUpAll(setupSqlite3ForTests);

  late AppDatabase db;
  late ModuleDataCleaner cleaner;
  late ModuleStateRepository states;
  late ModuleContext context;

  const notes = NotesModule();
  const finance = FinanceModule();

  /// finance 的七张表（与 `FinanceModule.ownedTables` 一致）。
  const financeTables = {
    'accounts',
    'categories',
    'transactions',
    'budgets',
    'recurring_rules',
    'positions',
    'price_cache',
  };

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    cleaner = ModuleDataCleaner(db);
    states = ModuleStateRepository(db);
    context = ModuleContext(database: db, logger: const DebugModuleLogger());
  });

  tearDown(() async {
    await db.close();
  });

  /// 七张 finance 表各塞一条，用来验证「清理别人时一条不动」。
  Future<void> seedFinance() async {
    final accountId = await db
        .into(db.accounts)
        .insert(
          AccountsCompanion.insert(
            name: '工资卡',
            type: AccountType.bank,
            balanceMinor: const Value(100000),
          ),
        );
    final categoryId = await db
        .into(db.categories)
        .insert(
          CategoriesCompanion.insert(name: '餐饮', kind: CategoryKind.expense),
        );
    await db
        .into(db.transactions)
        .insert(
          TransactionsCompanion.insert(
            type: TxnType.expense,
            accountId: accountId,
            amountMinor: 2500,
            occurredAt: DateTime(2026, 10, 30, 12),
            categoryId: Value(categoryId),
          ),
        );
    await db
        .into(db.budgets)
        .insert(
          BudgetsCompanion.insert(
            categoryId: categoryId,
            amountMinor: 200000,
            month: DateTime(2026, 10),
          ),
        );
    await db
        .into(db.recurringRules)
        .insert(
          RecurringRulesCompanion.insert(
            name: '房租',
            type: TxnType.expense,
            accountId: accountId,
            amountMinor: 300000,
            frequency: RecurFrequency.monthly,
            startDate: DateTime(2026, 1, 1),
            nextRunAt: DateTime(2026, 11, 1),
          ),
        );
    await db
        .into(db.positions)
        .insert(
          PositionsCompanion.insert(
            market: Market.sh,
            code: '600519',
            name: '贵州茅台',
            sharesCent: 15000,
            costPriceMinor: 160000,
          ),
        );
    await db
        .into(db.priceCache)
        .insert(
          PriceCacheCompanion.insert(
            symbol: 'sh600519',
            priceMinor: 170000,
            updatedAt: DateTime(2026, 10, 31, 15),
          ),
        );
  }

  Future<int> seedNote({
    String title = '一条笔记',
    String? refType,
    String? refId,
  }) {
    return db.noteDao.createNote(
      NotesCompanion.insert(
        title: title,
        refType: Value(refType),
        refId: Value(refId),
        createdAt: Value(DateTime(2026, 10, 31, 9)),
        updatedAt: Value(DateTime(2026, 10, 31, 9)),
      ),
    );
  }

  Future<int> noteCount() async =>
      (await cleaner.countRows({'notes'}))['notes'] ?? 0;

  group('停用 notes：数据一行不动', () {
    test('停用只写开关，笔记条数不变', () async {
      await seedNote(title: '甲');
      await seedNote(title: '乙');

      await states.setEnabled('notes', false);

      expect(await noteCount(), 2);
      expect(await states.enabledIds(appModules), isNot(contains('notes')));
    });

    test('停用再启用，数据仍在（停用不是删除）', () async {
      await seedNote(title: '甲');

      await states.setEnabled('notes', false);
      await states.setEnabled('notes', true);

      expect(await noteCount(), 1);
      expect(await states.enabledIds(appModules), contains('notes'));
    });

    test('停用 notes 不影响 finance 的开关与数据', () async {
      await seedFinance();
      await seedNote();
      await states.setEnabled('finance', true);

      await states.setEnabled('notes', false);

      final enabled = await states.enabledIds(appModules);
      expect(enabled, contains('finance'));
      expect(enabled, isNot(contains('notes')));

      final counts = await cleaner.countRows(financeTables);
      expect(counts.values.every((c) => c == 1), isTrue, reason: '$counts');
    });
  });

  group('清理 notes：只删自己的表', () {
    test('finance 的七张表一条不动', () async {
      await seedFinance();
      await seedNote(title: '甲');
      await seedNote(title: '乙');

      final removed = await cleaner.clearModule(notes, context);

      expect(removed, 2);
      expect(await noteCount(), 0);

      final counts = await cleaner.countRows(financeTables);
      expect(counts, {for (final table in financeTables) table: 1});
    });

    test('清理不重置模块开关（清理 ≠ 恢复默认）', () async {
      await seedNote();
      await states.setSortOrder('notes', 5);

      await cleaner.clearModule(notes, context);

      final enabled = await states.enabledIds(appModules);
      expect(enabled, contains('notes'));
      expect((await states.sortOrders())['notes'], 5);
    });

    test('清理后还能继续写新笔记', () async {
      await seedNote(title: '清理前');
      await cleaner.clearModule(notes, context);

      await seedNote(title: '清理后');

      final rows = await db.noteDao.watchNotes().first;
      expect(rows.map((n) => n.title), ['清理后']);
    });

    test('空库清理返回 0，不报错（重复点清理不该炸）', () async {
      expect(await cleaner.clearModule(notes, context), 0);
      expect(await cleaner.clearModule(notes, context), 0);
    });
  });

  group('清理 finance：不碰 notes', () {
    test('笔记一条不动', () async {
      await seedFinance();
      await seedNote(title: '甲');

      await cleaner.clearModule(finance, context);

      expect(await noteCount(), 1);
    });

    test('挂在被删标的上的笔记还在，仍能按 ref 查出来（弱引用不建外键）', () async {
      await seedFinance();
      await seedNote(title: '茅台的思考', refType: 'position', refId: 'sh600519');

      await cleaner.clearModule(finance, context);
      // 持仓已被物理删除，但笔记不该因为「对方不在了」而报错或消失。
      expect(await db.select(db.positions).get(), isEmpty);

      final linked = await db.noteDao
          .watchNotesForRef(refType: 'position', refId: 'sh600519')
          .first;
      expect(linked.map((n) => n.title), ['茅台的思考']);
    });
  });

  group('清理确认框里的文案', () {
    test('用 tableLabels 显示中文表名', () async {
      await seedNote(title: '甲');
      await seedNote(title: '乙');

      final counts = await cleaner.countRows(notes.ownedTables);
      expect(
        describeRowCounts(counts, labels: notes.tableLabels),
        '共 2 条（笔记 2）',
      );
    });

    test('没有笔记时给一句人话，而不是「共 0 条」', () async {
      final counts = await cleaner.countRows(notes.ownedTables);
      expect(describeRowCounts(counts, labels: notes.tableLabels), '暂无数据');
    });
  });

  group('路由门禁：停用后进不去', () {
    test('/notes 在 notes 停用时被踢回 launcher', () {
      expect(
        resolveModuleRedirect(
          location: '/notes',
          enabledIds: const {'finance'},
        ),
        '/',
      );
    });

    test('/notes 在 notes 启用时放行（含相关笔记的查询参数）', () {
      expect(
        resolveModuleRedirect(
          location: '/notes',
          enabledIds: const {'finance', 'notes'},
        ),
        isNull,
      );
    });
  });
}
