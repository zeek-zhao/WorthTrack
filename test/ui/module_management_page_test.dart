import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worthtrack/core/module/app_module.dart';
import 'package:worthtrack/core/module/module_providers.dart';
import 'package:worthtrack/ui/settings/module_management_page.dart';

import '../helpers/fake_module_data_cleaner.dart';
import '../helpers/fake_module_state_repository.dart';

class _Module extends AppModule {
  const _Module(this.id, this.name, this.order);

  @override
  final ModuleId id;

  @override
  final String name;

  final int order;

  @override
  IconData get icon => Icons.widgets;

  @override
  int get defaultOrder => order;

  @override
  Set<String> get ownedTables => const {'accounts', 'transactions'};

  @override
  Map<String, String> get tableLabels => const {
    'accounts': '账户',
    'transactions': '流水',
  };
}

/// issue #45：模块管理页的四条路径。
///
/// 这里刻意把「停用」与「清理」拆成两组断言：
/// 它们是两个动词，混在一起测会让「停用偷偷删了数据」这种 bug 蒙混过关。
void main() {
  const finance = _Module('finance', '记账与资产', 10);
  const notes = _Module('notes', '记事本', 20);

  late FakeModuleStateRepository stateRepo;
  late FakeModuleDataCleaner cleaner;

  Future<void> pumpPage(
    WidgetTester tester, {
    List<AppModule> modules = const [finance],
    Map<ModuleId, int> sortOrders = const {},
  }) async {
    if (sortOrders.isNotEmpty) {
      final enabled = stateRepo.enabled;
      await stateRepo.dispose();
      stateRepo = FakeModuleStateRepository(
        enabled: enabled,
        sortOrders: sortOrders,
      );
    }
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          moduleStateRepositoryProvider.overrideWithValue(stateRepo),
          moduleDataCleanerProvider.overrideWithValue(cleaner),
        ],
        child: MaterialApp(home: ModuleManagementPage(modules: modules)),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() {
    stateRepo = FakeModuleStateRepository(enabled: {'finance', 'notes'});
    cleaner = FakeModuleDataCleaner();
  });

  tearDown(() async {
    await stateRepo.dispose();
  });

  testWidgets('列出模块与状态，四个动作都在', (tester) async {
    await pumpPage(tester);

    expect(find.byKey(const Key('module_tile_finance')), findsOneWidget);
    expect(find.text('记账与资产'), findsOneWidget);
    expect(find.text('已启用'), findsOneWidget);
    expect(find.byKey(const Key('module_switch_finance')), findsOneWidget);
    expect(find.byKey(const Key('module_clear_finance')), findsOneWidget);
    expect(find.byKey(const Key('module_up_finance')), findsOneWidget);
    expect(find.byKey(const Key('module_down_finance')), findsOneWidget);
  });

  group('启用 / 停用', () {
    testWidgets('停用只写开关，**不调用清理**，状态文案说明数据仍在', (tester) async {
      await pumpPage(tester);

      await tester.tap(find.byKey(const Key('module_switch_finance')));
      await tester.pumpAndSettle();

      expect(stateRepo.enabledCalls, [(id: 'finance', enabled: false)]);
      expect(cleaner.clearCalls, 0, reason: '停用绝不能删数据');
      expect(find.text('已停用 · 数据仍保留'), findsOneWidget);
    });

    testWidgets('重新启用后回到已启用', (tester) async {
      stateRepo = FakeModuleStateRepository(enabled: {'notes'});
      await pumpPage(tester);
      expect(find.text('已停用 · 数据仍保留'), findsOneWidget);

      await tester.tap(find.byKey(const Key('module_switch_finance')));
      await tester.pumpAndSettle();

      expect(stateRepo.enabledCalls, [(id: 'finance', enabled: true)]);
      expect(find.text('已启用'), findsOneWidget);
    });

    testWidgets('全部停用后页面仍可操作（防死锁：这一页不依赖模块开关）', (tester) async {
      stateRepo = FakeModuleStateRepository(enabled: const {});
      await pumpPage(tester);

      expect(find.byKey(const Key('module_tile_finance')), findsOneWidget);
      expect(find.text('已停用 · 数据仍保留'), findsOneWidget);

      await tester.tap(find.byKey(const Key('module_switch_finance')));
      await tester.pumpAndSettle();
      expect(stateRepo.enabledCalls, [(id: 'finance', enabled: true)]);
    });
  });

  group('清理数据', () {
    testWidgets('先弹确认框并告知条数，取消则什么都不做', (tester) async {
      await pumpPage(tester);

      await tester.tap(find.byKey(const Key('module_clear_finance')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('module_clear_dialog')), findsOneWidget);
      expect(find.text('共 7 条（账户 2 · 流水 5）'), findsOneWidget);

      await tester.tap(find.byKey(const Key('module_clear_cancel')));
      await tester.pumpAndSettle();

      expect(cleaner.clearCalls, 0);
      expect(stateRepo.enabledCalls, isEmpty, reason: '清理不该改开关');
    });

    testWidgets('确认后调用清理，并提示删除条数', (tester) async {
      await pumpPage(tester);

      await tester.tap(find.byKey(const Key('module_clear_finance')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('module_clear_confirm')));
      await tester.pumpAndSettle();

      expect(cleaner.clearCalls, 1);
      expect(cleaner.clearedModule?.id, 'finance');
      expect(find.text('已删除 7 条记录'), findsOneWidget);
      expect(stateRepo.enabledCalls, isEmpty, reason: '清理不该改开关');
    });

    testWidgets('没有数据时提示「没有可清理的数据」', (tester) async {
      cleaner = FakeModuleDataCleaner(counts: const {'accounts': 0});
      await pumpPage(tester);

      await tester.tap(find.byKey(const Key('module_clear_finance')));
      await tester.pumpAndSettle();
      expect(find.text('暂无数据'), findsOneWidget);

      await tester.tap(find.byKey(const Key('module_clear_confirm')));
      await tester.pumpAndSettle();
      expect(find.text('没有可清理的数据'), findsOneWidget);
    });
  });

  group('排序', () {
    testWidgets('下移把完整顺序写回 module_state', (tester) async {
      await pumpPage(tester, modules: const [finance, notes]);

      await tester.tap(find.byKey(const Key('module_down_finance')));
      await tester.pumpAndSettle();

      expect(stateRepo.lastSortOrders, {'notes': 0, 'finance': 1});
      // 界面上顺序也换了。
      final tiles = tester
          .widgetList<Card>(find.byType(Card))
          .map((card) => card.key)
          .toList();
      expect(tiles, [
        const Key('module_tile_notes'),
        const Key('module_tile_finance'),
      ]);
    });

    testWidgets('第一个不能上移、最后一个不能下移', (tester) async {
      await pumpPage(tester, modules: const [finance, notes]);

      final up = tester.widget<IconButton>(
        find.byKey(const Key('module_up_finance')),
      );
      final down = tester.widget<IconButton>(
        find.byKey(const Key('module_down_notes')),
      );
      expect(up.onPressed, isNull);
      expect(down.onPressed, isNull);
    });

    testWidgets('已有自定义排序时按它渲染', (tester) async {
      await pumpPage(
        tester,
        modules: const [finance, notes],
        sortOrders: const {'notes': 0, 'finance': 1},
      );

      final tiles = tester
          .widgetList<Card>(find.byType(Card))
          .map((card) => card.key)
          .toList();
      expect(tiles, [
        const Key('module_tile_notes'),
        const Key('module_tile_finance'),
      ]);
    });
  });
}
