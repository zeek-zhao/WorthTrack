import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:worthtrack/core/last_module_store.dart';
import 'package:worthtrack/core/module/app_module.dart';
import 'package:worthtrack/core/module/module_providers.dart';
import 'package:worthtrack/core/router.dart';

import '../helpers/fake_module_state_repository.dart';

/// 一个自带二级页的最小模块，用来验证「每模块独立返回栈」。
class _DemoModule extends AppModule {
  const _DemoModule();

  @override
  ModuleId get id => 'demo';

  @override
  String get name => '演示模块';

  @override
  IconData get icon => Icons.science;

  @override
  int get defaultOrder => 10;

  @override
  List<RouteBase> get routes => [
    GoRoute(
      path: '/demo',
      builder: (context, state) => Scaffold(
        body: Column(
          children: [
            const Text('demo-root'),
            TextButton(
              onPressed: () => context.go('/demo/detail'),
              child: const Text('去详情'),
            ),
          ],
        ),
      ),
      routes: [
        GoRoute(
          path: 'detail',
          builder: (context, state) =>
              const Scaffold(body: Text('demo-detail')),
        ),
      ],
    ),
  ];
}

class _SecondModule extends AppModule {
  const _SecondModule();

  @override
  ModuleId get id => 'second';

  @override
  String get name => '第二模块';

  @override
  IconData get icon => Icons.widgets;

  @override
  int get defaultOrder => 20;

  @override
  List<RouteBase> get routes => [
    GoRoute(
      path: '/second',
      builder: (context, state) => const Scaffold(body: Text('second-root')),
    ),
  ];
}

/// issue #44：go_router 导航结构。
///
/// 用假模块而不是真 finance：这里要验证的是**路由骨架**，
/// 拉进真模块会把数据库、行情、PIN 全都拽进来，测试就不再是单元测试了。
void main() {
  const modules = <AppModule>[_DemoModule(), _SecondModule()];

  Future<GoRouter> pumpRouter(
    WidgetTester tester, {
    String initialLocation = '/',
    LastModuleStore? store,
  }) async {
    final router = createAppRouter(
      modules: modules,
      initialLocation: initialLocation,
      lastModuleStore: store,
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      // launcher 本身是 ConsumerWidget，所以即使只测路由也要有 ProviderScope。
      ProviderScope(
        overrides: [
          moduleStateRepositoryProvider.overrideWithValue(
            FakeModuleStateRepository(),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('初始位置 / 显示 launcher', (tester) async {
    await pumpRouter(tester);

    expect(find.text('WorthTrack'), findsOneWidget);
  });

  testWidgets('可以直接落在某个模块上（冷启动回到上次模块）', (tester) async {
    await pumpRouter(tester, initialLocation: '/demo');

    expect(find.text('demo-root'), findsOneWidget);
    expect(find.text('WorthTrack'), findsNothing);
  });

  testWidgets('模块内的二级页可以正常进出', (tester) async {
    final router = await pumpRouter(tester, initialLocation: '/demo');

    await tester.tap(find.text('去详情'));
    await tester.pumpAndSettle();
    expect(find.text('demo-detail'), findsOneWidget);

    router.go('/second');
    await tester.pumpAndSettle();
    expect(find.text('second-root'), findsOneWidget);

    // launcher 卡片是「进入模块首页」，所以从外面 go 回来落在根页，
    // 而不是用户上次停留的二级页——这是刻意的，不是 bug。
    router.go('/demo');
    await tester.pumpAndSettle();
    expect(find.text('demo-root'), findsOneWidget);
  });

  testWidgets('停在模块里会写入「上次模块」痕迹', (tester) async {
    final store = InMemoryLastModuleStore();
    await pumpRouter(tester, initialLocation: '/demo', store: store);
    await tester.pump();

    final visit = await store.read();
    expect(visit?.moduleId, 'demo');
  });

  testWidgets('没有传 store 时不崩（例如测试与无痕场景）', (tester) async {
    await pumpRouter(tester, initialLocation: '/demo');

    expect(find.text('demo-root'), findsOneWidget);
  });

  testWidgets('空模块列表也能起（不会因为没模块就崩）', (tester) async {
    final router = createAppRouter(
      modules: const <AppModule>[],
      initialLocation: '/',
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          moduleStateRepositoryProvider.overrideWithValue(
            FakeModuleStateRepository(),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('WorthTrack'), findsOneWidget);
  });

  test('模块按 defaultOrder 排序后成为 branch 顺序', () {
    final router = createAppRouter(modules: modules);
    addTearDown(router.dispose);

    // shell 路由是第 3 条（前两条是 / 与 /settings）。
    final shell = router.configuration.routes.whereType<StatefulShellRoute>();
    expect(shell, hasLength(1));
    final branchPaths = shell.single.branches
        .map((branch) => branch.routes.whereType<GoRoute>().first.path)
        .toList();
    expect(branchPaths, ['/demo', '/second']);
  });
}
