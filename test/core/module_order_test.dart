import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worthtrack/core/module/app_module.dart';
import 'package:worthtrack/core/module/module_registry.dart';

class _Module extends AppModule {
  const _Module(this.id, this.order);

  @override
  final ModuleId id;

  final int order;

  @override
  String get name => id;

  @override
  IconData get icon => Icons.widgets;

  @override
  int get defaultOrder => order;
}

/// issue #45：用户自定义排序与默认排序的合并规则。
///
/// 关键要求是**确定性**：同一份输入必须永远得到同一个顺序，
/// 否则 launcher 会在两次重建之间跳来跳去。
void main() {
  const modules = <AppModule>[
    _Module('b', 20),
    _Module('a', 10),
    _Module('c', 30),
  ];

  List<String> ids(List<AppModule> list) => [for (final m in list) m.id];

  test('没有自定义排序时按 defaultOrder', () {
    expect(ids(orderModules(modules, const {})), ['a', 'b', 'c']);
  });

  test('自定义排序覆盖 defaultOrder', () {
    expect(ids(orderModules(modules, const {'c': 0, 'b': 1, 'a': 2})), [
      'c',
      'b',
      'a',
    ]);
  });

  test('部分模块有自定义排序时，其余回落到 defaultOrder', () {
    // c 被拖到最前，a / b 仍按默认序。
    expect(ids(orderModules(modules, const {'c': 0})), ['c', 'a', 'b']);
  });

  test('order 相同时按 defaultOrder 再按 id 排，结果确定', () {
    expect(ids(orderModules(modules, const {'a': 0, 'b': 0, 'c': 0})), [
      'a',
      'b',
      'c',
    ]);
  });

  test('残留的已删除模块 id 不影响结果', () {
    expect(ids(orderModules(modules, const {'ghost': 0, 'b': 1})), [
      'b',
      'a',
      'c',
    ]);
  });

  test('不改动传入的列表', () {
    final input = <AppModule>[...modules];
    orderModules(input, const {'c': 0});
    expect(ids(input), ['b', 'a', 'c']);
  });
}
