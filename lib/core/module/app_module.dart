import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'package:worthtrack/data/db/app_database.dart';

/// 模块标识。
///
/// 约定：全小写、短横线分词、全仓唯一（如 `finance` / `watchlist` / `notes` / `game`）。
/// 同时作为 `module_state` 表的主键与路由前缀，**一旦发布不得改名**。
typedef ModuleId = String;

/// 模块级日志出口。
///
/// 模块不得直接 `print` / `debugPrint`：统一走这里，便于将来接到文件或诊断页。
abstract class ModuleLogger {
  void info(String message);
  void warn(String message, [Object? error]);
  void error(String message, [Object? error]);
}

/// 默认实现：转发到 `debugPrint`。release 下不产生额外开销。
class DebugModuleLogger implements ModuleLogger {
  const DebugModuleLogger();

  @override
  void info(String message) => debugPrint('[module] $message');

  @override
  void warn(String message, [Object? error]) =>
      debugPrint('[module][warn] $message${error == null ? '' : ' · $error'}');

  @override
  void error(String message, [Object? error]) =>
      debugPrint('[module][error] $message${error == null ? '' : ' · $error'}');
}

/// 装配层交给模块的唯一依赖入口。
///
/// **模块禁止 import `lib/di.dart`**，也禁止直接 import 其他模块的 DAO / 仓储，
/// 只能通过这里拿到的 `database` 操作**自己 `ownedTables` 声明过的表**。
/// 跨模块协作一律走对方公开的仓储接口（由模块自己通过本 context 暴露）。
///
/// 表所有权不是靠类型系统守住的（Drift 的 `AppDatabase` 暴露全部 DAO），
/// 而是靠架构测试 `test/architecture/module_boundary_test.dart` 静态扫描 + 本类文档约束。
class ModuleContext {
  const ModuleContext({required this.database, required this.logger});

  /// 全模块共用的单库连接。`@DriftDatabase(tables: [...])` 是集中装配点，无法模块化。
  final AppDatabase database;

  /// 模块日志出口。
  final ModuleLogger logger;

  /// 在单个事务里执行（碰钱路径必须用，铁律 4）。
  Future<T> transaction<T>(Future<T> Function() action) =>
      database.transaction(action);
}

/// 模块契约。
///
/// 一个模块 = 一个目录 + 注册表里的一行。契约字段的语义：
///
/// | 字段 | 语义 | 何时被读 |
/// |---|---|---|
/// | [id] | 唯一标识，`module_state` 主键 | 装配、停用、清理 |
/// | [name] / [icon] | launcher 与模块管理页展示 | UI |
/// | [defaultOrder] | 首次启用时的 launcher 排序 | 首次启用 |
/// | [dependsOn] | 依赖的模块 id，被依赖者停用时本模块一并隐藏 | 装配、停用 |
/// | [ownedTables] | 拥有的表名（与 `@DriftDatabase(tables:)` 一一对应） | 架构测试、清理 |
/// | [routes] | 模块内的路由（go_router branch） | 装配 |
/// | [settingsTiles] | 向**系统设置页**贡献的条目 | 设置页 |
/// | [onEnable] / [onDisable] | 启停钩子，**不得删数据** | 模块管理页 |
/// | [onClear] | 清理数据，**必须**只删自己的表 | 模块管理页 |
///
/// 注意「停用」与「清理」是两个动词：停用只隐藏、数据一行不动；清理才物理删除。
abstract class AppModule {
  const AppModule();

  /// 唯一标识，见 [ModuleId] 约定。
  ModuleId get id;

  /// launcher 与模块管理页显示的名称。
  String get name;

  /// launcher 图标。
  IconData get icon;

  /// 首次启用时的默认排序（小的在前）。
  int get defaultOrder;

  /// 依赖的模块 id。被依赖模块停用时，本模块不得单独启用。
  Set<ModuleId> get dependsOn => const <ModuleId>{};

  /// 本模块拥有的表名，必须与 `@DriftDatabase(tables: [...])` 中的真实表一一对应。
  Set<String> get ownedTables => const <String>{};

  /// 模块内路由。装配层把它们挂到 go_router 的独立 branch，各自保留返回栈。
  List<RouteBase> get routes => const <RouteBase>[];

  /// 向系统设置页贡献条目。系统设置本身（PIN / 备份恢复 / 模块管理）归 core，不属任何模块。
  List<Widget> settingsTiles(ModuleContext context) => const <Widget>[];

  /// 向 launcher 贡献**常驻快捷动作**（如「记一笔」「记一条」）。
  ///
  /// 由模块自己提供而不是 core 硬编码，避免 core 反向依赖模块：
  /// launcher 只知道「有几个快捷按钮」，不知道按钮背后是哪个模块。
  /// 停用模块时它的快捷动作一并消失。
  List<Widget> quickActions(BuildContext context) => const <Widget>[];

  /// 启用钩子。可建表、可补数据，但**不得删除用户数据**。
  Future<void> onEnable(ModuleContext context) async {}

  /// 停用钩子。**数据一行不动**，只允许清理内存态、取消订阅。
  Future<void> onDisable(ModuleContext context) async {}

  /// 清理钩子。物理删除 [ownedTables] 的数据，由模块自己实现。
  Future<void> onClear(ModuleContext context) async {}
}
