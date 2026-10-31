import 'package:flutter_test/flutter_test.dart';
import 'package:worthtrack/core/module/module_route.dart';

/// issue #49：跨模块跳转的路径拼装。
///
/// 模块之间禁止互相 import，所以「打开别人的页面」只能靠一条 URL。
/// 这条 URL 拼错了只会在运行时安静地跳到 404，因此单独测。
void main() {
  test('不带参数就是模块根路由', () {
    expect(moduleRoute('notes'), '/notes');
    expect(moduleRoute('finance'), '/finance');
  });

  test('带查询参数时拼成标准 URL', () {
    final uri = Uri.parse(moduleRoute('notes', query: {'refId': 'sh600519'}));
    expect(uri.path, '/notes');
    expect(uri.queryParameters['refId'], 'sh600519');
  });

  test('中文标签被正确编码，解析回来仍是原文', () {
    final route = moduleRoute(
      'notes',
      query: {'refType': 'position', 'refId': 'sh600519', 'refLabel': '贵州茅台'},
    );
    // 直接拼字符串会把中文塞进 URL，交给 Uri 编码才是对的。
    expect(route, isNot(contains('贵州茅台')));

    final uri = Uri.parse(route);
    expect(uri.queryParameters, {
      'refType': 'position',
      'refId': 'sh600519',
      'refLabel': '贵州茅台',
    });
  });

  test('空 map 不会留下一个多余的问号', () {
    expect(moduleRoute('notes', query: const {}), '/notes');
  });
}
