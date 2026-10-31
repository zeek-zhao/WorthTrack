import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worthtrack/core/module/app_module.dart';
import 'package:worthtrack/core/module/module_registry.dart';
import 'package:worthtrack/data/db/app_database.dart';

import '../helpers/sqlite3_loader.dart';
import 'module_boundary_rules.dart';

/// issue #46：架构测试守住模块边界（M5 收口）。
///
/// 这些断言不看运行时行为，只看**源码与 schema 的形状**：
/// 边界靠约定守不住，靠一个会在 PR 里变红的测试才守得住。
void main() {
  setUpAll(setupSqlite3ForTests);

  /// 读 `lib/modules/**` 下所有 dart 源码（含 drift 生成的 `.g.dart`：
  /// 生成代码里同样写着 `attachedDatabase.transactions`，绕不过去）。
  List<SourceFile> readModuleSources() {
    final dir = Directory('lib/modules');
    return [
      for (final entity in dir.listSync(recursive: true))
        if (entity is File && entity.path.endsWith('.dart'))
          SourceFile(
            entity.path.replaceAll('\\', '/'),
            entity.readAsStringSync(),
          ),
    ];
  }

  List<SourceFile> readCoreSources() {
    final dir = Directory('lib/core');
    return [
      for (final entity in dir.listSync(recursive: true))
        if (entity is File && entity.path.endsWith('.dart'))
          SourceFile(
            entity.path.replaceAll('\\', '/'),
            entity.readAsStringSync(),
          ),
    ];
  }

  Map<ModuleId, Set<String>> ownedTablesByModule() => {
    for (final module in appModules) module.id: module.ownedTables,
  };

  group('模块边界（真实仓库）', () {
    test('模块之间没有越界：不 import di.dart / 不 import 他人 / 不碰他人表', () {
      final violations = checkModuleBoundary(
        files: readModuleSources(),
        ownedTablesByModule: ownedTablesByModule(),
      );
      expect(violations, isEmpty, reason: violations.join('\n'));
    });

    test('core 不反向依赖模块（注册表与装配入口除外）', () {
      final violations = checkCoreDoesNotImportModules(
        coreFiles: readCoreSources(),
        moduleIds: {for (final module in appModules) module.id},
      );
      expect(violations, isEmpty, reason: violations.join('\n'));
    });

    test('扫描确实读到了源码（防止路径写错导致「零违规」假绿）', () {
      final files = readModuleSources();
      expect(files.length, greaterThan(40), reason: '模块源码数量异常，扫描路径可能不对');
      expect(
        files.any((file) => file.path.endsWith('finance_module.dart')),
        isTrue,
      );
    });
  });

  group('ownedTables 与真实 schema 双向一致', () {
    late AppDatabase db;

    setUp(() {
      // allTables 只是生成的表清单，不会真的开库；内存连接足够。
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test('模块声明的每张表都真实存在', () {
      final real = {for (final table in db.allTables) table.actualTableName};
      for (final module in appModules) {
        for (final table in module.ownedTables) {
          expect(
            real,
            contains(table),
            reason: '模块 ${module.id} 声明了不存在的表 $table',
          );
        }
      }
    });

    test('schema 里的每张表都有主（模块或 core），没有孤儿表', () {
      final real = {for (final table in db.allTables) table.actualTableName};
      final claimed = <String>{
        for (final module in appModules) ...module.ownedTables,
        ...coreTables,
      };

      final orphans = real.difference(claimed);
      expect(
        orphans,
        isEmpty,
        reason:
            '这些表没有任何模块声明所有权：$orphans'
            '（备份恢复与「清理数据」都按所有权工作，漏了会出事）',
      );
    });

    test('core 的表不被任何模块声明', () {
      for (final module in appModules) {
        expect(
          module.ownedTables.intersection(coreTables),
          isEmpty,
          reason: '模块 ${module.id} 抢了 core 的表：${module.ownedTables}',
        );
      }
    });

    test('注册表本身合法（id / 顺序 / 依赖 / 表所有权唯一）', () {
      expect(validateModuleRegistry(appModules), isEmpty);
    });
  });

  group('自检：故意违规时规则必须变红', () {
    const demo = {
      'demo': {'notes'},
    };

    List<String> check(String path, String content) => checkModuleBoundary(
      files: [SourceFile(path, content)],
      ownedTablesByModule: demo,
    );

    test('import di.dart 被抓到', () {
      final violations = check(
        'lib/modules/demo/a.dart',
        "import 'package:worthtrack/di.dart';",
      );
      expect(violations, hasLength(1));
      expect(violations.single, contains('di.dart'));
    });

    test('import 他人模块被抓到（包路径）', () {
      final violations = check(
        'lib/modules/demo/a.dart',
        "import 'package:worthtrack/modules/finance/finance_module.dart';",
      );
      expect(violations, isNotEmpty);
      expect(violations.join(), contains('finance'));
    });

    test('import 他人模块被抓到（相对路径）', () {
      // 相对路径必须先按所在目录归一化：`ui/` 往上两级才回到 `lib/modules/`。
      final violations = check(
        'lib/modules/demo/ui/a.dart',
        "import '../../finance/finance_module.dart';",
      );
      expect(violations, isNotEmpty);
      expect(violations.join(), contains('finance'));
    });

    test('访问他人表被抓到（访问器写法）', () {
      final violations = check(
        'lib/modules/demo/a.dart',
        'final rows = db.transactions.select();',
      );
      expect(violations, isNotEmpty);
      expect(violations.join(), contains('transactions'));
    });

    test('引用他人表类 / Companion 被抓到', () {
      expect(
        check('lib/modules/demo/a.dart', 'final c = TransactionsCompanion;'),
        isNotEmpty,
      );
      expect(
        check('lib/modules/demo/a.dart', 'final t = Positions();'),
        isNotEmpty,
      );
    });

    test('碰 core 的 module_state 也被抓到', () {
      final violations = check(
        'lib/modules/demo/a.dart',
        'final rows = db.moduleStates.select();',
      );
      expect(violations, isNotEmpty);
      expect(violations.join(), contains('core'));
    });

    test('自己的表、自己的模块名不误报', () {
      final violations = check('lib/modules/demo/a.dart', '''
import 'package:worthtrack/modules/demo/data/notes_dao.dart';
import 'package:worthtrack/core/providers.dart';
final rows = db.notes.select();
final copy = NotesCompanion;
''');
      expect(violations, isEmpty);
    });

    test('文档注释里提到别人的表不算违规', () {
      final violations = check('lib/modules/demo/a.dart', '''
/// 这里刻意提到 Transactions 与 db.positions，但只是文档。
// db.transactions 也一样
final x = 1;
''');
      expect(violations, isEmpty);
    });

    test('core 反向 import 模块被抓到', () {
      final violations = checkCoreDoesNotImportModules(
        coreFiles: const [
          SourceFile(
            'lib/core/router.dart',
            "import 'package:worthtrack/modules/finance/finance_module.dart';",
          ),
        ],
        moduleIds: {'finance'},
      );
      expect(violations, isNotEmpty);
    });

    test('core 的注册表允许 import 模块（装配点例外）', () {
      final violations = checkCoreDoesNotImportModules(
        coreFiles: const [
          SourceFile(
            'lib/core/module/module_registry.dart',
            "import 'package:worthtrack/modules/finance/finance_module.dart';",
          ),
        ],
        moduleIds: {'finance'},
      );
      expect(violations, isEmpty);
    });
  });

  group('规则自身的解析能力', () {
    test('resolveImport 认得包路径、相对路径与 dart:', () {
      expect(
        resolveImport(
          'lib/modules/demo/a.dart',
          'package:worthtrack/core/x.dart',
        ),
        'lib/core/x.dart',
      );
      expect(
        resolveImport(
          'lib/modules/demo/ui/a.dart',
          '../../finance/finance_module.dart',
        ),
        'lib/modules/finance/finance_module.dart',
      );
      expect(
        resolveImport('lib/modules/demo/a.dart', '../finance/x.dart'),
        'lib/modules/finance/x.dart',
      );
      // dart: 与其他包解析不出模块，不会被误判成越界。
      expect(
        foreignModuleIn(
          importerPath: 'lib/modules/demo/a.dart',
          uri: 'dart:async',
          selfId: 'demo',
        ),
        isNull,
      );
      expect(
        foreignModuleIn(
          importerPath: 'lib/modules/demo/a.dart',
          uri: 'package:flutter/material.dart',
          selfId: 'demo',
        ),
        isNull,
      );
    });

    test('moduleIdOf 兼容 Windows 反斜杠', () {
      expect(moduleIdOf(r'lib\modules\finance\finance_module.dart'), 'finance');
      expect(moduleIdOf('lib/modules/notes/a.dart'), 'notes');
      expect(moduleIdOf('lib/core/router.dart'), isNull);
    });

    test('importsOf 只认 import，不认注释与字符串', () {
      final imports = importsOf('''
// import 'package:worthtrack/di.dart';
import 'package:worthtrack/core/providers.dart';
import "package:worthtrack/data/db/app_database.dart";
final s = "import 'nope.dart';";
''');
      expect(imports, [
        'package:worthtrack/core/providers.dart',
        'package:worthtrack/data/db/app_database.dart',
      ]);
    });

    test('knownTables 覆盖 schema 的全部表（新增表别忘了登记）', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final real = {for (final table in db.allTables) table.actualTableName};
      final known = {for (final table in knownTables) table.tableName};
      expect(
        real.difference(known),
        isEmpty,
        reason: '新加了表却没登记进 knownTables，越界扫描会漏掉它',
      );
    });
  });
}
