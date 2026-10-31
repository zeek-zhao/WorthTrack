/// 模块边界的**纯规则**（issue #46）。
///
/// 放在独立文件里而不是塞进 `_test.dart`：规则要能被「自检用例」用假源码喂进去，
/// 否则「违规时测试会红」这件事永远没被验证过。
///
/// 三条边界：
/// 1. 模块不得 import 装配入口 `di.dart`（否则模块反向依赖全部模块）；
/// 2. 模块不得 import 其他模块；
/// 3. 模块只能访问自己 `ownedTables` 里的表（`module_state` 归 core，谁都不许碰）。
library;

/// 一份待扫描的源码。
class SourceFile {
  const SourceFile(this.path, this.content);

  /// 仓库相对路径，统一用 `/`（Windows 的反斜杠在构造前已归一）。
  final String path;

  final String content;

  @override
  String toString() => 'SourceFile($path)';
}

/// 一张表在 Dart 代码里的三种写法。
///
/// - [tableName]：数据库里的真实表名（`recurring_rules`）
/// - [getter]：`AppDatabase` 上的访问器（`recurringRules`）
/// - [className]：Drift 的 Table 类名（`RecurringRules`），行类/Companion 都带这个前缀
class TableRef {
  const TableRef(this.tableName, this.getter, this.className);

  final String tableName;
  final String getter;
  final String className;
}

/// 当前 schema 的全部表。新增表时必须同步这里，否则扫描会漏。
const List<TableRef> knownTables = [
  TableRef('accounts', 'accounts', 'Accounts'),
  TableRef('categories', 'categories', 'Categories'),
  TableRef('transactions', 'transactions', 'Transactions'),
  TableRef('budgets', 'budgets', 'Budgets'),
  TableRef('recurring_rules', 'recurringRules', 'RecurringRules'),
  TableRef('positions', 'positions', 'Positions'),
  TableRef('price_cache', 'priceCache', 'PriceCache'),
  TableRef('notes', 'notes', 'Notes'),
  TableRef('module_state', 'moduleStates', 'ModuleStates'),
];

/// 归 core 的表：不属任何模块，模块**一律不许碰**。
const Set<String> coreTables = {'module_state'};

/// 去掉整行注释与块注释。
///
/// 只做行级处理：`///  Transactions 表` 这种文档注释不该算违规，
/// 但为了不误伤字符串里的 `//`，不尝试解析行内注释。
String stripComments(String source) {
  final out = <String>[];
  var inBlock = false;
  for (final line in source.split('\n')) {
    final trimmed = line.trimLeft();
    if (inBlock) {
      if (trimmed.contains('*/')) inBlock = false;
      continue;
    }
    if (trimmed.startsWith('/*')) {
      if (!trimmed.contains('*/')) inBlock = true;
      continue;
    }
    if (trimmed.startsWith('//')) continue;
    out.add(line);
  }
  return out.join('\n');
}

/// 取出所有 `import '...'` 的 URI。
List<String> importsOf(String source) {
  final pattern = RegExp(r'''^\s*import\s+['"]([^'"]+)['"]''', multiLine: true);
  return [for (final match in pattern.allMatches(source)) match.group(1)!];
}

/// 把 import URI 解析成仓库相对路径。
///
/// - `package:worthtrack/x.dart` → `lib/x.dart`
/// - 相对路径 → 相对 import 语句所在目录归一化（`..` 逐级回退）
/// - `dart:` 与其他包 → 原样返回（里面永远没有 `modules/`，不会被误判）
///
/// 必须做这一步：`import '../../finance/x.dart'` 光看 URI 是认不出 `finance` 的。
String resolveImport(String importerPath, String uri) {
  final target = uri.replaceAll('\\', '/');
  const packagePrefix = 'package:worthtrack/';
  if (target.startsWith(packagePrefix)) {
    return 'lib/${target.substring(packagePrefix.length)}';
  }
  if (target.contains(':')) return target;

  final importer = importerPath.replaceAll('\\', '/');
  final slash = importer.lastIndexOf('/');
  final segments = <String>[
    if (slash > 0) ...importer.substring(0, slash).split('/'),
  ];
  for (final segment in target.split('/')) {
    if (segment.isEmpty || segment == '.') continue;
    if (segment == '..') {
      if (segments.isNotEmpty) segments.removeLast();
      continue;
    }
    segments.add(segment);
  }
  return segments.join('/');
}

/// `lib/modules/<id>/...` → `<id>`；不在模块目录下返回 null。
String? moduleIdInPath(String path) {
  final match = RegExp(
    r'(?:^|/)modules/([a-z0-9_-]+)/',
  ).firstMatch(path.replaceAll('\\', '/'));
  return match?.group(1);
}

/// `lib/modules/<id>/...` → `<id>`；不在模块目录下返回 null。
String? moduleIdOf(String path) => moduleIdInPath(path);

/// 这个 import 是否指向「别人的模块」；是则返回对方的 id。
///
/// 只看解析后的路径，不依赖「已知模块清单」——
/// 新增一个模块目录却忘了登记，越界照样要被抓住。
String? foreignModuleIn({
  required String importerPath,
  required String uri,
  required String selfId,
}) {
  final id = moduleIdInPath(resolveImport(importerPath, uri));
  if (id == null || id == selfId) return null;
  return id;
}

/// 扫描所有模块源码，返回违规描述（空列表 = 通过）。
List<String> checkModuleBoundary({
  required List<SourceFile> files,
  required Map<String, Set<String>> ownedTablesByModule,
  List<TableRef> tables = knownTables,
  Set<String> coreTableNames = coreTables,
}) {
  final violations = <String>[];

  for (final file in files) {
    final id = moduleIdOf(file.path);
    if (id == null) continue;
    final owned = ownedTablesByModule[id] ?? const <String>{};
    final code = stripComments(file.content);

    for (final uri in importsOf(code)) {
      if (uri == 'package:worthtrack/di.dart') {
        violations.add(
          '${file.path}: 模块 $id 不得 import di.dart'
          '（装配入口会反向依赖所有模块，core 服务请用 core/providers.dart）',
        );
      }
      final foreign = foreignModuleIn(
        importerPath: file.path,
        uri: uri,
        selfId: id,
      );
      if (foreign != null) {
        violations.add('${file.path}: 模块 $id 不得 import 模块 $foreign（$uri）');
      }
    }

    for (final table in tables) {
      if (owned.contains(table.tableName)) continue;
      final owner = coreTableNames.contains(table.tableName) ? 'core' : '其他模块';
      if (RegExp('\\.${table.getter}\\b').hasMatch(code)) {
        violations.add('${file.path}: 模块 $id 访问了 ${table.tableName}（属 $owner）');
      } else if (RegExp(
        '\\b${table.className}(Companion)?\\b',
      ).hasMatch(code)) {
        violations.add('${file.path}: 模块 $id 引用了 ${table.className}（属 $owner）');
      }
    }
  }
  return violations;
}

/// core 不得反向依赖模块（唯一例外是注册表这类装配点）。
///
/// [moduleIds] 传「已注册的模块 id」：`lib/modules/xxx/` 里出现了未注册的目录，
/// 说明有人新建了模块却忘了登记，同样是违规（备份与清理都会漏掉它）。
List<String> checkCoreDoesNotImportModules({
  required List<SourceFile> coreFiles,
  required Set<String> moduleIds,
  Set<String> allowedPaths = const {'lib/core/module/module_registry.dart'},
}) {
  final violations = <String>[];
  for (final file in coreFiles) {
    if (allowedPaths.contains(file.path.replaceAll('\\', '/'))) continue;
    for (final uri in importsOf(stripComments(file.content))) {
      final id = moduleIdInPath(resolveImport(file.path, uri));
      if (id == null) continue;
      if (moduleIds.isNotEmpty && !moduleIds.contains(id)) {
        violations.add('${file.path}: import 了未注册的模块目录 $id（$uri）');
      } else {
        violations.add('${file.path}: core 不得反向 import 模块 $id（$uri）');
      }
    }
  }
  return violations;
}
