import '../stats.dart';

/// 预算领域接口（issue #10）。
abstract class BudgetRepository {
  /// 监听指定月份各预算的消耗状态（含分类信息）。
  Stream<List<BudgetStatus>> watchBudgetStatuses(DateTime month);

  /// 设置/更新某分类某月预算（幂等）。
  Future<void> upsertBudget(
    DateTime month, {
    required int categoryId,
    required int amountMinor,
  });

  /// 删除预算。
  Future<void> deleteBudget(int id);
}
