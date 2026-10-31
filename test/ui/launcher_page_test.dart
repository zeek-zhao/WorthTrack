import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worthtrack/core/module/app_module.dart';
import 'package:worthtrack/core/module/module_providers.dart';
import 'package:worthtrack/core/module/module_state_repository.dart';
import 'package:worthtrack/ui/launcher/launcher_page.dart';

import '../helpers/fake_module_state_repository.dart';

/// issue #44：launcher 首页。
///
/// launcher **不认识任何具体模块**：卡片来自注册表、快捷动作来自模块自己，
/// 所以这里断言的是「按注册表渲染」而不是「渲染了 finance 的某个控件」。
void main() {
  Future<void> pumpLauncher(
    WidgetTester tester, {
    Set<ModuleId>? enabled,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          moduleStateRepositoryProvider.overrideWithValue(
            FakeModuleStateRepository(enabled: enabled),
          ),
        ],
        child: const MaterialApp(home: LauncherPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('默认渲染出 finance 模块卡片', (tester) async {
    await pumpLauncher(tester);

    expect(find.byKey(const Key('launcher-module-finance')), findsOneWidget);
    expect(find.text('记账与资产'), findsOneWidget);
  });

  testWidgets('快捷动作「记一笔」常驻在首页（1 步记账）', (tester) async {
    await pumpLauncher(tester);

    // `FilledButton.tonalIcon` 生成的是 FilledButton 的子类，byType 匹配不到，
    // 所以用谓词找「祖先里有一个 FilledButton」。
    expect(
      find.ancestor(
        of: find.text('记一笔'),
        matching: find.byWidgetPredicate((widget) => widget is FilledButton),
      ),
      findsOneWidget,
    );
  });

  testWidgets('有设置入口', (tester) async {
    await pumpLauncher(tester);

    expect(find.byKey(const Key('launcher-settings')), findsOneWidget);
  });

  testWidgets('停用模块后卡片消失，快捷动作也一起消失', (tester) async {
    await pumpLauncher(tester, enabled: const <ModuleId>{});

    expect(find.byKey(const Key('launcher-module-finance')), findsNothing);
    expect(find.text('记一笔'), findsNothing);
    expect(find.text('所有模块都停用了，去设置里重新启用'), findsOneWidget);
  });

  testWidgets('数据库尚未返回时按「全部启用」渲染，不闪空列表', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          moduleStateRepositoryProvider.overrideWithValue(
            _NeverEmittingRepository(),
          ),
        ],
        child: const MaterialApp(home: LauncherPage()),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('launcher-module-finance')), findsOneWidget);
    expect(find.text('所有模块都停用了，去设置里重新启用'), findsNothing);
  });
}

class _NeverEmittingRepository implements ModuleStateRepository {
  /// 永远不发射、也不关闭：模拟「首帧 DB 还没回」。
  @override
  Stream<Set<ModuleId>> watchEnabledIds(List<AppModule> modules) =>
      Stream<Set<ModuleId>>.multi((_) {});

  @override
  Future<Set<ModuleId>> enabledIds(List<AppModule> modules) async => const {};

  @override
  Future<void> setEnabled(ModuleId id, bool enabled) async {}

  @override
  Future<void> setSortOrder(ModuleId id, int order) async {}

  @override
  Future<Map<ModuleId, int>> sortOrders() async => const {};

  @override
  Future<void> setSortOrders(Map<ModuleId, int> orders) async {}

  @override
  Stream<Map<ModuleId, int>> watchSortOrders() =>
      Stream<Map<ModuleId, int>>.empty();
}
