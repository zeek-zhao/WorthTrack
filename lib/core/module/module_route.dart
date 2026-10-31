import 'package:worthtrack/core/module/app_module.dart';

/// 拼一条跨模块的跳转路径。
///
/// **模块之间禁止互相 import**（`test/architecture/` 扫源码守着），所以 A 模块
/// 想打开 B 模块的页面时，唯一合法的通道就是「路径 + 查询参数」：
/// 传一个字符串过去，不传一个类型过去。
///
/// 把拼装收敛在这里，而不是让每个调用点自己写 `'/notes?refType=...'`：
/// 路径一旦写错，只会在运行时安静地跳到 404。
String moduleRoute(ModuleId id, {Map<String, String> query = const {}}) {
  return Uri(
    path: '/$id',
    queryParameters: query.isEmpty ? null : query,
  ).toString();
}
