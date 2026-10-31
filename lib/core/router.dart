import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:worthtrack/core/last_module_store.dart';
import 'package:worthtrack/core/module/app_module.dart';
import 'package:worthtrack/core/module/module_registry.dart';
import 'package:worthtrack/ui/launcher/launcher_page.dart';
import 'package:worthtrack/ui/settings/module_management_page.dart';
import 'package:worthtrack/ui/settings/settings_page.dart';

/// 构建应用路由。
///
/// 结构：
/// - `/`                  launcher（应用级首页）
/// - `/settings`          系统设置（core 级，不属任何模块）
/// - `/settings/modules`  模块管理（core 级，**停用全部模块后仍必须可达**）
/// - 每个模块一个 [StatefulShellBranch]，挂在 [StatefulShellRoute.indexedStack] 下，
///   **各自保留独立返回栈**（在 finance 里进二级页，切走再回来仍停在原处）
///
/// [initialLocation] 由启动时读「上次模块」决定（30 分钟超时后回 launcher）。
/// 传了 [enabledIds] 之后，被停用模块的路由会被重定向回 launcher（#45）。
GoRouter createAppRouter({
  List<AppModule> modules = appModules,
  LastModuleStore? lastModuleStore,
  String initialLocation = '/',
  ValueListenable<Set<ModuleId>?>? enabledIds,
}) {
  final ordered = modulesByOrder(modules);

  return GoRouter(
    initialLocation: initialLocation,
    // 开关一变就要重新判定当前路由，否则用户会「停在已停用的模块里」。
    refreshListenable: enabledIds,
    redirect: enabledIds == null
        ? null
        : (context, state) => resolveModuleRedirect(
            location: state.matchedLocation,
            enabledIds: enabledIds.value,
            modules: modules,
          ),
    routes: [
      GoRoute(path: '/', builder: (context, state) => const LauncherPage()),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsPage(),
        routes: [
          GoRoute(
            path: 'modules',
            builder: (context, state) => const ModuleManagementPage(),
          ),
        ],
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

/// 已停用模块的路由该不该被踢回 launcher。
///
/// 返回 `null` 表示放行。三条规则：
/// 1. [enabledIds] 为 null（还没读到）时一律放行——宁可多显示一次，也不能把用户挡在门外；
/// 2. `/` 与 `/settings`（含子路由）是 core 路由，**永远放行**。这是防死锁的关键：
///    停用全部模块后，用户仍然要能进「模块管理」把它们打开；
/// 3. 其余路径看首段是不是一个「已注册但被停用」的模块 id。
String? resolveModuleRedirect({
  required String location,
  required Set<ModuleId>? enabledIds,
  List<AppModule> modules = appModules,
}) {
  if (enabledIds == null) return null;
  final segments = location.split('/').where((s) => s.isNotEmpty).toList();
  if (segments.isEmpty) return null; // '/'
  if (segments.first == 'settings') return null;

  final module = moduleById(segments.first, modules);
  if (module == null) return null; // 不是模块路由，交给 go_router 自己报错
  return enabledIds.contains(module.id) ? null : '/';
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
