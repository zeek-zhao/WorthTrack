import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:worthtrack/core/last_module_store.dart';
import 'package:worthtrack/core/module/app_module.dart';
import 'package:worthtrack/core/module/module_data_cleaner.dart';
import 'package:worthtrack/core/module/module_registry.dart';
import 'package:worthtrack/core/module/module_state_repository.dart';
import 'package:worthtrack/core/providers.dart';

/// 模块开关状态仓储（`module_state` 归 core）。
final moduleStateRepositoryProvider = Provider<ModuleStateRepository>(
  (ref) => ModuleStateRepository(ref.watch(appDatabaseProvider)),
);

/// 模块数据的计数与清理（#45）。
final moduleDataCleanerProvider = Provider<ModuleDataCleaner>(
  (ref) => ModuleDataCleaner(ref.watch(appDatabaseProvider)),
);

/// 装配层交给模块的依赖入口（启停/清理钩子用）。
final moduleContextProvider = Provider<ModuleContext>(
  (ref) => ModuleContext(
    database: ref.watch(appDatabaseProvider),
    logger: const DebugModuleLogger(),
  ),
);

/// 已启用的模块 id。表里没有记录的模块视为启用（新装默认全开）。
final enabledModuleIdsProvider = StreamProvider<Set<ModuleId>>(
  (ref) => ref.watch(moduleStateRepositoryProvider).watchEnabledIds(appModules),
);

/// 用户自定义排序（`module_state.sort_order`）。
final moduleSortOrdersProvider = StreamProvider<Map<ModuleId, int>>(
  (ref) => ref.watch(moduleStateRepositoryProvider).watchSortOrders(),
);

/// 已启用的模块（按「自定义排序 > 默认排序」排好），launcher 与路由门禁都读它。
final enabledModulesProvider = Provider<List<AppModule>>((ref) {
  final enabled =
      ref.watch(enabledModuleIdsProvider).value ??
      {for (final module in appModules) module.id};
  final orders = ref.watch(moduleSortOrdersProvider).value ?? const {};
  return orderModules([
    for (final module in appModules)
      if (enabled.contains(module.id)) module,
  ], orders);
});

/// 「上次停留在哪个模块」的存储。设备本地痕迹，不进数据库、不随备份走。
final lastModuleStoreProvider = Provider<LastModuleStore>(
  (ref) => FileLastModuleStore(),
);
