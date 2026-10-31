import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worthtrack/core/module/app_module.dart';
import 'package:worthtrack/core/module/module_registry.dart';

/// 只实现必填字段的最小模块，用来验证契约的默认值是否够用。
class _MinimalModule extends AppModule {
  const _MinimalModule({
    this.id = 'demo',
    this.name = '演示',
    this.defaultOrder = 10,
    this.depends = const <ModuleId>{},
    this.tables = const <String>{},
  });

  @override
  final ModuleId id;

  @override
  final String name;

  @override
  final int defaultOrder;

  final Set<ModuleId> depends;

  final Set<String> tables;

  @override
  IconData get icon => Icons.widgets;

  @override
  Set<ModuleId> get dependsOn => depends;

  @override
  Set<String> get ownedTables => tables;
}

void main() {
  group('AppModule 契约默认值', () {
    test('只实现必填字段即可成立，可选字段都有安全默认值', () {
      const module = _MinimalModule();
      expect(module.dependsOn, isEmpty);
      expect(module.ownedTables, isEmpty);
      expect(module.routes, isEmpty);
      expect(module.id, 'demo');
    });
  });

  group('validateModuleRegistry', () {
    test('空注册表合法（M5 #41 阶段 finance 尚未注册）', () {
      expect(validateModuleRegistry(const <AppModule>[]), isEmpty);
    });

    test('最小模块单独注册合法', () {
      expect(validateModuleRegistry(const [_MinimalModule()]), isEmpty);
    });

    test('id 格式非法被拦下', () {
      final errors = validateModuleRegistry(const [
        _MinimalModule(id: 'Finance App'),
      ]);
      expect(errors, hasLength(1));
      expect(errors.single, contains('格式非法'));
    });

    test('id 为空被拦下', () {
      final errors = validateModuleRegistry(const [_MinimalModule(id: '')]);
      expect(errors.any((e) => e.contains('不能为空')), isTrue);
    });

    test('id 重复被拦下', () {
      final errors = validateModuleRegistry(const [
        _MinimalModule(defaultOrder: 1),
        _MinimalModule(defaultOrder: 2),
      ]);
      expect(errors.any((e) => e.contains('id 重复')), isTrue);
    });

    test('defaultOrder 冲突被拦下', () {
      final errors = validateModuleRegistry(const [
        _MinimalModule(id: 'a', defaultOrder: 5),
        _MinimalModule(id: 'b', defaultOrder: 5),
      ]);
      expect(errors.any((e) => e.contains('defaultOrder 冲突')), isTrue);
    });

    test('name 空白被拦下', () {
      final errors = validateModuleRegistry(const [
        _MinimalModule(name: '   '),
      ]);
      expect(errors.any((e) => e.contains('name 不能为空')), isTrue);
    });

    test('依赖未注册的模块被拦下', () {
      final errors = validateModuleRegistry(const [
        _MinimalModule(depends: {'ghost'}),
      ]);
      expect(errors.single, contains('未注册的模块'));
    });

    test('自依赖被拦下', () {
      final errors = validateModuleRegistry(const [
        _MinimalModule(depends: {'demo'}),
      ]);
      expect(errors.single, contains('依赖了自己'));
    });

    test('依赖成环被拦下', () {
      final errors = validateModuleRegistry(const [
        _MinimalModule(id: 'a', defaultOrder: 1, depends: {'b'}),
        _MinimalModule(id: 'b', defaultOrder: 2, depends: {'a'}),
      ]);
      expect(errors.single, contains('依赖成环'));
      expect(errors.single, contains('a → b → a'));
    });

    test('一张表只能有一个所有者', () {
      final errors = validateModuleRegistry(const [
        _MinimalModule(id: 'a', defaultOrder: 1, tables: {'transactions'}),
        _MinimalModule(id: 'b', defaultOrder: 2, tables: {'transactions'}),
      ]);
      expect(errors.single, contains('表所有权必须唯一'));
    });

    test('多个问题一次性全部报出，不只报第一个', () {
      final errors = validateModuleRegistry(const [
        _MinimalModule(id: 'A', defaultOrder: 1),
        _MinimalModule(id: 'b', defaultOrder: 1, depends: {'ghost'}),
      ]);
      expect(errors.length, greaterThanOrEqualTo(3));
    });
  });

  group('注册表查询', () {
    test('modulesByOrder 按 defaultOrder 升序', () {
      final ordered = modulesByOrder(const [
        _MinimalModule(id: 'late', defaultOrder: 30),
        _MinimalModule(id: 'early', defaultOrder: 10),
        _MinimalModule(id: 'mid', defaultOrder: 20),
      ]);
      expect(ordered.map((m) => m.id), ['early', 'mid', 'late']);
    });

    test('modulesByOrder 不改动传入列表', () {
      final source = [
        const _MinimalModule(id: 'late', defaultOrder: 30),
        const _MinimalModule(id: 'early', defaultOrder: 10),
      ];
      modulesByOrder(source);
      expect(source.first.id, 'late');
    });

    test('moduleById 命中与未命中', () {
      const modules = [_MinimalModule(id: 'demo')];
      expect(moduleById('demo', modules)?.id, 'demo');
      expect(moduleById('nope', modules), isNull);
    });

    test('真实注册表当前必须通过校验（#42 注册 finance 后仍然成立）', () {
      expect(validateModuleRegistry(appModules), isEmpty);
    });
  });
}
