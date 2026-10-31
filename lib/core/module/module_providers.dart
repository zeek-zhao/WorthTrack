import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:worthtrack/core/last_module_store.dart';
import 'package:worthtrack/core/module/app_module.dart';
import 'package:worthtrack/core/module/module_registry.dart';
import 'package:worthtrack/core/module/module_state_repository.dart';
import 'package:worthtrack/di.dart';

/// 模块开关状态仓储（`module_state` 归 core）。
final moduleStateRepositoryProvider = Provider<ModuleStateRepository>(
  (ref) => ModuleStateRepository(ref.watch(appDatabaseProvider)),
);

/// 已启用的模块 id。表里没有记录的模块视为启用（新装默认全开）。
final enabledModuleIdsProvider = StreamProvider<Set<ModuleId>>(
  (ref) => ref.watch(moduleStateRepositoryProvider).watchEnabledIds(appModules),
);

/// 「上次停留在哪个模块」的存储。设备本地痕迹，不进数据库、不随备份走。
final lastModuleStoreProvider = Provider<LastModuleStore>(
  (ref) => FileLastModuleStore(),
);
