import 'dart:async';

import 'package:worthtrack/core/module/app_module.dart';
import 'package:worthtrack/core/module/module_state_repository.dart';

/// 可变的模块状态仓储，供 UI 测试用。
///
/// 与真实实现语义对齐（表里没记录 = 启用），但**不碰数据库**：
/// 需要验证真实读写语义的用例在 `test/core/module_state_repository_test.dart`。
/// 这里额外记录调用，方便断言「点一下开关到底写了什么」。
class FakeModuleStateRepository implements ModuleStateRepository {
  FakeModuleStateRepository({
    Set<ModuleId>? enabled,
    Map<ModuleId, int> sortOrders = const {},
  }) : _enabled = enabled == null ? null : Set<ModuleId>.of(enabled),
       _orders = Map<ModuleId, int>.of(sortOrders);

  /// null = 全部启用（与真实仓储的默认语义一致）。
  Set<ModuleId>? _enabled;

  final Map<ModuleId, int> _orders;

  final StreamController<void> _changes = StreamController<void>.broadcast();

  /// 每次 `setEnabled` 的调用记录，按发生顺序。
  final List<({ModuleId id, bool enabled})> enabledCalls = [];

  /// 最后一次 `setSortOrders` 写入的完整顺序。
  Map<ModuleId, int>? lastSortOrders;

  /// 当前启用集合（null 表示全部启用）。
  Set<ModuleId>? get enabled => _enabled;

  /// 最近一次见到的注册表全集，用于把「全部启用（null）」物化成具体集合。
  Set<ModuleId> _known = const {};

  Set<ModuleId> _resolve(List<AppModule> modules) {
    _known = {for (final module in modules) module.id};
    return _enabled ?? _known;
  }

  @override
  Stream<Set<ModuleId>> watchEnabledIds(List<AppModule> modules) async* {
    yield _resolve(modules);
    await for (final _ in _changes.stream) {
      yield _resolve(modules);
    }
  }

  @override
  Future<Set<ModuleId>> enabledIds(List<AppModule> modules) async =>
      _resolve(modules);

  @override
  Future<void> setEnabled(ModuleId id, bool enabled) async {
    enabledCalls.add((id: id, enabled: enabled));
    final current = Set<ModuleId>.of(_enabled ?? _known);
    if (enabled) {
      current.add(id);
    } else {
      current.remove(id);
    }
    _enabled = current;
    _changes.add(null);
  }

  @override
  Future<void> setSortOrder(ModuleId id, int order) async {
    _orders[id] = order;
    _changes.add(null);
  }

  @override
  Future<Map<ModuleId, int>> sortOrders() async => Map.of(_orders);

  @override
  Future<void> setSortOrders(Map<ModuleId, int> orders) async {
    lastSortOrders = Map.of(orders);
    _orders
      ..clear()
      ..addAll(orders);
    _changes.add(null);
  }

  @override
  Stream<Map<ModuleId, int>> watchSortOrders() async* {
    yield Map.of(_orders);
    await for (final _ in _changes.stream) {
      yield Map.of(_orders);
    }
  }

  /// 关掉内部广播流（测试收尾用，避免 analyzer 提示未关闭）。
  Future<void> dispose() => _changes.close();
}
