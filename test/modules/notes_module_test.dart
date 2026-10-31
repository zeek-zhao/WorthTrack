import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:worthtrack/core/module/module_registry.dart';
import 'package:worthtrack/data/db/app_database.dart';
import 'package:worthtrack/modules/notes/notes_module.dart';

import '../helpers/sqlite3_loader.dart';

/// issue #47：notes 模块的契约。
///
/// 这里是「新增模块 = 加一个目录 + 注册表里加一行」这句承诺的最小证明：
/// 契约字段齐全、路由挂得上、表所有权对得上、注册表仍然合法。
void main() {
  setUpAll(setupSqlite3ForTests);

  const module = NotesModule();

  test('契约字段：id / 名称 / 排序 / 依赖', () {
    expect(module.id, 'notes');
    expect(module.name, '记事本');
    expect(module.defaultOrder, 20);
    // 记事本不依赖任何模块：停用 finance 之后它仍然能用。
    expect(module.dependsOn, isEmpty);
  });

  test('表所有权只有 notes，且中文标签齐全', () {
    expect(module.ownedTables, {'notes'});
    expect(module.tableLabels['notes'], '笔记');
    // 每个 ownedTables 都要有标签，否则「清理数据」确认框会露英文表名。
    expect(module.tableLabels.keys.toSet(), module.ownedTables);
  });

  test('路由是 /notes 单条，挂在模块 id 前缀下', () {
    final paths = module.routes
        .whereType<GoRoute>()
        .map((route) => route.path)
        .toList();
    expect(paths, ['/notes']);
    for (final path in paths) {
      expect(path, startsWith('/${module.id}'));
    }
  });

  test('已注册进 appModules，且注册表整体仍然合法', () {
    expect(appModules.map((m) => m.id), contains('notes'));
    expect(validateModuleRegistry(appModules), isEmpty);
  });

  test('ownedTables 里的表在真实 schema 中确实存在', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final real = {for (final table in db.allTables) table.actualTableName};
    expect(real, containsAll(module.ownedTables));
  });
}
