import 'package:worthtrack/core/module/app_module.dart';
import 'package:worthtrack/core/module/module_state_repository.dart';

/// 固定启用集合的模块状态仓储。
///
/// UI 测试不该为了「launcher 显示哪几个模块」去开真数据库；
/// 需要验证真实读写语义的用例在 `test/core/module_state_repository_test.dart`。
class FakeModuleStateRepository implements ModuleStateRepository {
  FakeModuleStateRepository({this.enabled});

  /// 传 null 表示「全部启用」（与真实仓储的默认语义一致）。
  final Set<ModuleId>? enabled;

  @override
  Stream<Set<ModuleId>> watchEnabledIds(List<AppModule> modules) =>
      Stream.value(enabled ?? {for (final module in modules) module.id});

  @override
  Future<Set<ModuleId>> enabledIds(List<AppModule> modules) async =>
      enabled ?? {for (final module in modules) module.id};

  @override
  Future<void> setEnabled(ModuleId id, bool enabled) async {}

  @override
  Future<void> setSortOrder(ModuleId id, int order) async {}

  @override
  Stream<Map<ModuleId, int>> watchSortOrders() => Stream.value(const {});
}
