import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:worthtrack/core/last_module_store.dart';
import 'package:worthtrack/core/module/app_module.dart';
import 'package:worthtrack/core/module/module_registry.dart';
import 'package:worthtrack/ui/launcher/launcher_page.dart';
import 'package:worthtrack/ui/settings/settings_page.dart';

/// 构建应用路由。
///
/// 结构：
/// - `/`          launcher（应用级首页）
/// - `/settings`  系统设置（core 级，不属任何模块）
/// - 每个模块一个 [StatefulShellBranch]，挂在 [StatefulShellRoute.indexedStack] 下，
///   **各自保留独立返回栈**（在 finance 里进二级页，切走再回来仍停在原处）
///
/// [initialLocation] 由启动时读「上次模块」决定（30 分钟超时后回 launcher）。
GoRouter createAppRouter({
  List<AppModule> modules = appModules,
  LastModuleStore? lastModuleStore,
  String initialLocation = '/',
}) {
  final ordered = modulesByOrder(modules);

  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(path: '/', builder: (context, state) => const LauncherPage()),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsPage(),
      ),
      if (ordered.isNotEmpty)
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) => _ModuleShell(
            navigationShell: navigationShell,
            modules: ordered,
            store: lastModuleStore,
          ),
          branches: [
            for (final module in ordered)
              StatefulShellBranch(
                navigatorKey: GlobalKey<NavigatorState>(debugLabel: module.id),
                routes: module.routes,
              ),
          ],
        ),
    ],
  );
}

/// 模块外壳：不渲染任何额外 UI，只负责「记下当前停留在哪个模块」。
///
/// 不在每个模块里各写一遍上报逻辑——模块不该关心「上次访问」这种应用级关注点。
class _ModuleShell extends StatefulWidget {
  const _ModuleShell({
    required this.navigationShell,
    required this.modules,
    this.store,
  });

  final StatefulNavigationShell navigationShell;
  final List<AppModule> modules;
  final LastModuleStore? store;

  @override
  State<_ModuleShell> createState() => _ModuleShellState();
}

class _ModuleShellState extends State<_ModuleShell> {
  String? _lastWrittenId;

  @override
  Widget build(BuildContext context) {
    final index = widget.navigationShell.currentIndex;
    if (index >= 0 && index < widget.modules.length) {
      final id = widget.modules[index].id;
      final store = widget.store;
      if (store != null && _lastWrittenId != id) {
        _lastWrittenId = id;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          store.write(id, DateTime.now());
        });
      }
    }
    return widget.navigationShell;
  }
}

/// 启动位置：上次模块还在 30 分钟内就回到它，否则回 launcher。
///
/// 放在 core 而不是模块里：它要跨模块工作，且只依赖「模块 id 是否仍然注册」。
String resolveInitialLocation(
  LastModuleVisit? visit,
  DateTime now, {
  List<AppModule> modules = appModules,
  Duration ttl = LastModuleVisit.defaultTtl,
}) {
  if (visit == null || !visit.isFresh(now, ttl: ttl)) return '/';
  final exists = modules.any((module) => module.id == visit.moduleId);
  return exists ? '/${visit.moduleId}' : '/';
}
