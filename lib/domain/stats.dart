import '../data/db/app_database.dart';

/// 月度收支汇总（不含转账）。
class MonthTotals {
  const MonthTotals({
    required this.month,
    required this.expenseMinor,
    required this.incomeMinor,
  });

  /// 归属月份（当月 1 日 00:00）。
  final DateTime month;
  final int expenseMinor;
  final int incomeMinor;

  int get netMinor => incomeMinor - expenseMinor;

  static MonthTotals zero(DateTime month) =>
      MonthTotals(month: month, expenseMinor: 0, incomeMinor: 0);
}

/// 按分类聚合的支出/收入统计（报表页饼图数据源）。
class CategoryStat {
  const CategoryStat({
    required this.categoryId,
    required this.name,
    this.icon,
    required this.totalMinor,
    required this.count,
  });

  /// null 表示「未分类」交易。
  final int? categoryId;
  final String name;
  final String? icon;
  final int totalMinor;
  final int count;
}

/// 单条预算的当月消耗状态（预算页/报表页展示）。
class BudgetStatus {
  const BudgetStatus({
    required this.budget,
    required this.category,
    required this.spentMinor,
  });

  final Budget budget;
  final Category category;
  final int spentMinor;

  bool get overBudget => spentMinor > budget.amountMinor;

  /// 剩余额度，可为负（超支）。
  int get remainingMinor => budget.amountMinor - spentMinor;

  /// 消耗比例（0 ~ n），预算为 0 时恒为 0。
  double get usage =>
      budget.amountMinor <= 0 ? 0 : spentMinor / budget.amountMinor;
}
