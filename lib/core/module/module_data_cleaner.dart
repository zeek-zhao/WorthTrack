import 'package:worthtrack/core/module/app_module.dart';
import 'package:worthtrack/data/db/app_database.dart';

/// 模块数据的计数与清理（#45）。
///
/// **「只删自己的表」这条不变量由 core 强制，不靠每个模块自觉**：
/// 清理入口只接受 [AppModule]，表清单直接取它的 `ownedTables`，
/// 模块没有机会（也不需要）自己拼 SQL 去删别人的表。
///
/// 模块的 `onClear` 钩子仍然会被调用，但职责只是「删完之后的收尾」
/// （清内存态、重置缓存），而不是自己动数据库。
class ModuleDataCleaner {
  ModuleDataCleaner(this._db);

  final AppDatabase _db;

  /// 库里真实存在的表名（防止 `ownedTables` 写错时抛 SQL 错误）。
  Set<String> get _existingTables => {
    for (final table in _db.allTables) table.actualTableName,
  };

  /// 各表当前条数。表不存在或读失败时该表不出现在结果里。
  Future<Map<String, int>> countRows(Set<String> tables) async {
    final existing = _existingTables;
    final counts = <String, int>{};
    for (final table in tables) {
      if (!existing.contains(table)) continue;
      final rows = await _db
          .customSelect('SELECT COUNT(*) AS c FROM "$table"')
          .get();
      counts[table] = rows.first.read<int>('c');
    }
    return counts;
  }

  /// 模块当前总条数（清理前二次确认用）。
  Future<int> totalRows(AppModule module) async {
    final counts = await countRows(module.ownedTables);
    return counts.values.fold<int>(0, (sum, value) => sum + value);
  }

  /// 清空 [module] 的全部数据，返回删除的总条数。
  ///
  /// 单事务 + `defer_foreign_keys`：`accounts` 与 `transactions` 之间有外键，
  /// 提交前不逐个校验，删表顺序就不再致命；中途失败整体回滚，
  /// 不会留下「账户删了、流水还在」的半截状态。
  Future<int> clearModule(
    AppModule module,
    ModuleContext context, {
    void Function(String message)? log,
  }) async {
    final existing = _existingTables;
    final tables = [
      for (final table in module.ownedTables)
        if (existing.contains(table)) table,
    ];
    if (tables.isEmpty) {
      await module.onClear(context);
      return 0;
    }

    final before = await countRows(tables.toSet());
    final removed = before.values.fold(0, (sum, value) => sum + value);

    await _db.transaction(() async {
      await _db.customStatement('PRAGMA defer_foreign_keys = ON');
      for (final table in tables) {
        await _db.customStatement('DELETE FROM "$table"');
      }
    });

    log?.call('已清理 ${module.id}：${tables.join(', ')} 共 $removed 条');
    await module.onClear(context);
    return removed;
  }
}

/// 把「表名 → 条数」拼成一句给用户看的说明。
///
/// 例：`共 137 条（账户 3 · 流水 120 · 分类 14）`。
/// 表名没有中文标签时直接用表名，不假装认识它。
String describeRowCounts(
  Map<String, int> counts, {
  Map<String, String> labels = const {},
}) {
  final total = counts.values.fold(0, (sum, value) => sum + value);
  if (total == 0) return '暂无数据';
  final parts = [
    for (final entry in counts.entries)
      if (entry.value > 0) '${labels[entry.key] ?? entry.key} ${entry.value}',
  ];
  if (parts.isEmpty) return '暂无数据';
  return '共 $total 条（${parts.join(' · ')}）';
}
