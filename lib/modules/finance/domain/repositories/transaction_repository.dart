import 'package:worthtrack/data/db/app_database.dart';
import 'package:worthtrack/modules/finance/data/dao/transaction_dao.dart';
import 'package:worthtrack/modules/finance/domain/stats.dart';

/// 交易领域接口。
abstract class TransactionRepository {
  /// 监听最近交易（倒序）。
  Stream<List<Transaction>> watchRecent({int limit});

  /// 按组合条件过滤交易（关键词/类型/账户/分类/时间区间）。
  Stream<List<Transaction>> watchByFilter(TxnFilter filter);

  /// 监听指定月份收支汇总（转账不计入）。
  Stream<MonthTotals> watchMonthTotals(DateTime month);

  /// 监听整年收支汇总。
  Stream<MonthTotals> watchYearTotals(int year);

  /// 监听最近 [months] 个月（截至 [anchor] 当月）的逐月收支趋势。
  Stream<List<MonthTotals>> watchTrend({int months, DateTime? anchor});

  /// 监听指定月份按分类聚合统计（支出/收入）。
  Stream<List<CategoryStat>> watchCategoryStats(
    DateTime month, {
    CategoryKind kind,
  });

  /// 任意区间的分类聚合统计（年度报表用）。
  Stream<List<CategoryStat>> watchCategoryStatsRange(
    DateTime start,
    DateTime end, {
    CategoryKind kind,
  });

  /// 记账并原子调整账户余额，返回交易 id。
  Future<int> addTransaction(NewTransaction input);

  /// 编辑交易并同步调整账户余额（冲销旧影响 + 应用新影响）。
  Future<void> updateTransaction(int txnId, NewTransaction input);

  /// 删除交易并回滚余额影响（幂等）。
  Future<void> deleteTransaction(int txnId);
}
