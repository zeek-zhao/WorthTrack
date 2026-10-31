import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:worthtrack/core/last_module_store.dart';
import 'package:worthtrack/core/module/app_module.dart';
import 'package:worthtrack/core/module/module_registry.dart';
import 'package:worthtrack/core/router.dart';

class _StubModule extends AppModule {
  const _StubModule(this.id, this.order);

  @override
  final ModuleId id;

  final int order;

  @override
  String get name => id;

  @override
  IconData get icon => Icons.widgets;

  @override
  int get defaultOrder => order;
}

/// issue #44：冷启动落地页决策（纯函数，不碰 UI 与数据库）。
///
/// 四条规则：没有记录回 launcher、超时回 launcher、模块已不注册回 launcher、
/// 其余情况回到上次模块。
void main() {
  const modules = <AppModule>[_StubModule('finance', 10)];
  final now = DateTime(2025, 6, 1, 10);

  test('没有记录时回 launcher', () {
    expect(resolveInitialLocation(null, now, modules: modules), '/');
  });

  test('30 分钟内且模块仍注册，回到该模块', () {
    final visit = LastModuleVisit(
      moduleId: 'finance',
      at: now.subtract(const Duration(minutes: 5)),
    );
    expect(resolveInitialLocation(visit, now, modules: modules), '/finance');
  });

  test('超过 30 分钟回 launcher', () {
    final visit = LastModuleVisit(
      moduleId: 'finance',
      at: now.subtract(const Duration(minutes: 31)),
    );
    expect(resolveInitialLocation(visit, now, modules: modules), '/');
  });

  test('恰好 30 分钟仍回到该模块（与 isFresh 的上界一致）', () {
    final visit = LastModuleVisit(
      moduleId: 'finance',
      at: now.subtract(const Duration(minutes: 30)),
    );
    expect(resolveInitialLocation(visit, now, modules: modules), '/finance');
  });

  test('模块已被移除（升级后删模块）时回 launcher，不能指向不存在的路由', () {
    final visit = LastModuleVisit(
      moduleId: 'watchlist',
      at: now.subtract(const Duration(minutes: 1)),
    );
    expect(resolveInitialLocation(visit, now, modules: modules), '/');
  });

  test('时钟回拨时回 launcher', () {
    final visit = LastModuleVisit(
      moduleId: 'finance',
      at: now.add(const Duration(minutes: 5)),
    );
    expect(resolveInitialLocation(visit, now, modules: modules), '/');
  });

  test('默认参数就是真实注册表：finance 是合法落地页', () {
    final visit = LastModuleVisit(
      moduleId: 'finance',
      at: DateTime.now().subtract(const Duration(minutes: 1)),
    );
    expect(resolveInitialLocation(visit, DateTime.now()), '/finance');
  });

  test('ttl 可覆盖', () {
    final visit = LastModuleVisit(
      moduleId: 'finance',
      at: now.subtract(const Duration(minutes: 2)),
    );
    expect(
      resolveInitialLocation(
        visit,
        now,
        modules: modules,
        ttl: const Duration(minutes: 1),
      ),
      '/',
    );
  });

  test('真实注册表本身是合法的（id / 顺序 / 依赖 / 表所有权）', () {
    expect(validateModuleRegistry(appModules), isEmpty);
  });

  test('每个模块的路由都挂在 /<模块id> 下，launcher 才能直接 go 过去', () {
    for (final module in appModules) {
      final paths = module.routes
          .whereType<GoRoute>()
          .map((route) => route.path)
          .toList();
      expect(
        paths,
        isNotEmpty,
        reason: '模块 ${module.id} 没有任何路由，launcher 点了会白屏',
      );
      for (final path in paths) {
        expect(
          path,
          startsWith('/${module.id}'),
          reason: '模块 ${module.id} 的路由 $path 必须以 /${module.id} 开头',
        );
      }
    }
  });
}
