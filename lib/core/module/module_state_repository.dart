import 'package:drift/drift.dart';

import 'package:worthtrack/core/module/app_module.dart';
import 'package:worthtrack/data/db/app_database.dart';

/// 模块开关状态的读写（`module_state` 表归 core，不属任何模块）。
///
/// 语义约定：**表里没有记录的模块视为「启用」**。
/// 新装应用不该要求用户先逐个打开模块；只有用户明确关掉过，才会有 `enabled = false` 的记录。
class ModuleStateRepository {
  ModuleStateRepository(this._db);

  final AppDatabase _db;

  /// 已启用的模块 id 集合（流式，停用/启用后 UI 自动刷新）。
  Stream<Set<ModuleId>> watchEnabledIds(List<AppModule> modules) {
    return _db.select(_db.moduleStates).watch().map((rows) {
      final disabled = {
        for (final row in rows)
          if (!row.enabled) row.moduleId,
      };
      return {
        for (final module in modules)
          if (!disabled.contains(module.id)) module.id,
      };
    });
  }

  /// 已启用的模块 id 集合（一次性读取，供路由初始化用）。
  Future<Set<ModuleId>> enabledIds(List<AppModule> modules) async {
    final rows = await _db.select(_db.moduleStates).get();
    final disabled = {
      for (final row in rows)
        if (!row.enabled) row.moduleId,
    };
    return {
      for (final module in modules)
        if (!disabled.contains(module.id)) module.id,
    };
  }

  /// 启用/停用。**只改这一列，不碰任何业务数据**。
  Future<void> setEnabled(ModuleId id, bool enabled) async {
    // firstEnabledAt 是「第一次启用」的时间戳，重复开关不该把它刷新成最近一次。
    // 用 insertOnConflictUpdate 整体覆盖会丢掉旧值，所以先读一次再写回。
    final existing = await (_db.select(
      _db.moduleStates,
    )..where((t) => t.moduleId.equals(id))).getSingleOrNull();
    final firstEnabledAt =
        existing?.firstEnabledAt ?? (enabled ? DateTime.now() : null);

    await _db
        .into(_db.moduleStates)
        .insertOnConflictUpdate(
          ModuleStatesCompanion.insert(
            moduleId: id,
            enabled: Value(enabled),
            firstEnabledAt: Value(firstEnabledAt),
          ),
        );
  }

  /// launcher 排序（用户自定义，覆盖 `AppModule.defaultOrder`）。
  Future<void> setSortOrder(ModuleId id, int order) {
    return _db
        .into(_db.moduleStates)
        .insertOnConflictUpdate(
          ModuleStatesCompanion.insert(moduleId: id, sortOrder: Value(order)),
        );
  }

  /// 用户自定义的排序；没有记录的模块不返回。
  Stream<Map<ModuleId, int>> watchSortOrders() {
    return _db
        .select(_db.moduleStates)
        .watch()
        .map((rows) => {for (final row in rows) row.moduleId: row.sortOrder});
  }
}
