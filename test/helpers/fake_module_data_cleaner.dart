import 'package:worthtrack/core/module/app_module.dart';
import 'package:worthtrack/core/module/module_data_cleaner.dart';

/// 只记录调用、不做真实删除的清理器。
///
/// Widget 测试关心「点了之后调了什么」；真实删除语义
/// 在 `test/core/module_data_cleaner_test.dart` 用真库验证。
class FakeModuleDataCleaner implements ModuleDataCleaner {
  FakeModuleDataCleaner({
    this.counts = const {'accounts': 2, 'transactions': 5},
  });

  /// `countRows` 的返回值，用来驱动确认框文案。
  final Map<String, int> counts;

  int countCalls = 0;
  int clearCalls = 0;
  AppModule? clearedModule;

  @override
  Future<Map<String, int>> countRows(Set<String> tables) async {
    countCalls++;
    return counts;
  }

  @override
  Future<int> totalRows(AppModule module) async =>
      counts.values.fold<int>(0, (sum, value) => sum + value);

  @override
  Future<int> clearModule(
    AppModule module,
    ModuleContext context, {
    void Function(String message)? log,
  }) async {
    clearCalls++;
    clearedModule = module;
    return counts.values.fold<int>(0, (sum, value) => sum + value);
  }
}
