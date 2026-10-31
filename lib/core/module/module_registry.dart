import 'package:worthtrack/core/module/app_module.dart';
import 'package:worthtrack/modules/finance/finance_module.dart';

/// 全模块注册表：**显式注册，不用 build_runner 生成**。
///
/// 模块数量是个位数，显式列表更不容易被改错，也让「新增模块 = 加一个目录 + 这里加一行」
/// 这条成本约束可以被 diff 直接验证（issue #55）。
///
/// 这里是**装配点**，允许 import 各模块；core 的其他部分不允许反向依赖模块。
const List<AppModule> appModules = <AppModule>[FinanceModule()];

/// 按 [AppModule.defaultOrder] 升序返回模块列表。
///
/// launcher 与模块管理页都读这个顺序；用户自定义排序在 #45 通过 `module_state` 覆盖，
/// 见 [orderModules]。
List<AppModule> modulesByOrder([List<AppModule> modules = appModules]) {
  final sorted = List<AppModule>.of(modules);
  sorted.sort((a, b) => a.defaultOrder.compareTo(b.defaultOrder));
  return sorted;
}

/// 合并「用户自定义排序」与「模块默认排序」。
///
/// 规则：
/// 1. `sortOrders` 里有记录的模块用记录值，没有的用 `defaultOrder`；
/// 2. 值相同时按 `defaultOrder` 再按 id 排，保证**同一份输入永远得到同一个顺序**
///    （否则 launcher 会在两次重建之间跳来跳去）。
///
/// 只认 [modules] 里存在的 id：`module_state` 里可能残留已删除模块的记录。
List<AppModule> orderModules(
  List<AppModule> modules,
  Map<ModuleId, int> sortOrders,
) {
  int orderOf(AppModule module) => sortOrders[module.id] ?? module.defaultOrder;
  final sorted = List<AppModule>.of(modules);
  sorted.sort((a, b) {
    final byOrder = orderOf(a).compareTo(orderOf(b));
    if (byOrder != 0) return byOrder;
    final byDefault = a.defaultOrder.compareTo(b.defaultOrder);
    if (byDefault != 0) return byDefault;
    return a.id.compareTo(b.id);
  });
  return sorted;
}

/// 按 id 查模块，未注册返回 null。
AppModule? moduleById(ModuleId id, [List<AppModule> modules = appModules]) {
  for (final module in modules) {
    if (module.id == id) return module;
  }
  return null;
}

/// 模块 id 的合法格式：小写字母开头，允许小写字母、数字与短横线。
final RegExp _moduleIdPattern = RegExp(r'^[a-z][a-z0-9-]*$');

/// 校验注册表不变量，返回错误描述列表（空列表 = 通过）。
///
/// 这些不变量在 #46 由架构测试断言；在此之前先以纯函数形式可测，
/// 避免把「注册表写错」的问题拖到运行时才炸。
List<String> validateModuleRegistry(List<AppModule> modules) {
  final errors = <String>[];
  final seenIds = <ModuleId>{};
  final seenOrders = <int, ModuleId>{};
  final tableOwners = <String, ModuleId>{};

  for (final module in modules) {
    final id = module.id;
    if (id.isEmpty) {
      errors.add('模块 id 不能为空（name=${module.name}）');
    } else if (!_moduleIdPattern.hasMatch(id)) {
      errors.add('模块 id 格式非法：「$id」（应匹配 ${_moduleIdPattern.pattern}）');
    }
    if (module.name.trim().isEmpty) {
      errors.add('模块 $id 的 name 不能为空');
    }
    if (!seenIds.add(id)) {
      errors.add('模块 id 重复：「$id」');
    }
    final orderOwner = seenOrders[module.defaultOrder];
    if (orderOwner != null) {
      errors.add('defaultOrder 冲突：$orderOwner 与 $id 都是 ${module.defaultOrder}');
    } else {
      seenOrders[module.defaultOrder] = id;
    }
    for (final table in module.ownedTables) {
      if (table.trim().isEmpty) {
        errors.add('模块 $id 的 ownedTables 含空表名');
        continue;
      }
      final owner = tableOwners[table];
      if (owner != null && owner != id) {
        errors.add('表 $table 被多个模块声明：$owner 与 $id（表所有权必须唯一）');
      } else {
        tableOwners[table] = id;
      }
    }
  }

  for (final module in modules) {
    for (final dep in module.dependsOn) {
      if (dep == module.id) {
        errors.add('模块 ${module.id} 依赖了自己');
      } else if (!seenIds.contains(dep)) {
        errors.add('模块 ${module.id} 依赖了未注册的模块「$dep」');
      }
    }
  }

  if (errors.isEmpty) {
    final cycle = _findDependencyCycle(modules);
    if (cycle != null) {
      errors.add('模块依赖成环：${cycle.join(' → ')}');
    }
  }
  return errors;
}

/// 深度优先找依赖环，返回环上的 id 序列（含回到起点的那一跳），无环返回 null。
List<ModuleId>? _findDependencyCycle(List<AppModule> modules) {
  final byId = {for (final m in modules) m.id: m};
  final visiting = <ModuleId>[];
  final done = <ModuleId>{};

  List<ModuleId>? visit(ModuleId id) {
    if (done.contains(id)) return null;
    final at = visiting.indexOf(id);
    if (at != -1) return [...visiting.sublist(at), id];
    final module = byId[id];
    if (module == null) return null;
    visiting.add(id);
    for (final dep in module.dependsOn) {
      final cycle = visit(dep);
      if (cycle != null) return cycle;
    }
    visiting.removeLast();
    done.add(id);
    return null;
  }

  for (final module in modules) {
    final cycle = visit(module.id);
    if (cycle != null) return cycle;
  }
  return null;
}
