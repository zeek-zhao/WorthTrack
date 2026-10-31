import 'package:worthtrack/modules/finance/data/dao/transaction_dao.dart';
import 'package:worthtrack/data/db/app_database.dart';
import 'package:worthtrack/modules/finance/domain/repositories/transaction_repository.dart';
import 'package:worthtrack/modules/finance/domain/stats.dart';

/// [TransactionRepository] 的 Drift 实现。
class TransactionRepositoryImpl implements TransactionRepository {
  TransactionRepositoryImpl(this._dao);

  final TransactionDao _dao;

  @override
  Stream<List<Transaction>> watchRecent({int limit = 100}) =>
      _dao.watchRecent(limit: limit);

  @override
  Stream<List<Transaction>> watchByFilter(TxnFilter filter) =>
      _dao.watchByFilter(filter);

  @override
  Stream<MonthTotals> watchMonthTotals(DateTime month) =>
      _dao.watchMonthTotals(month);

  @override
  Stream<MonthTotals> watchYearTotals(int year) => _dao.watchYearTotals(year);

  @override
  Stream<List<MonthTotals>> watchTrend({int months = 6, DateTime? anchor}) =>
      _dao.watchTrend(months: months, anchor: anchor);

  @override
  Stream<List<CategoryStat>> watchCategoryStats(
    DateTime month, {
    CategoryKind kind = CategoryKind.expense,
  }) => _dao.watchCategoryStats(month, kind: kind);

  @override
  Stream<List<CategoryStat>> watchCategoryStatsRange(
    DateTime start,
    DateTime end, {
    CategoryKind kind = CategoryKind.expense,
  }) => _dao.watchCategoryStatsRange(start, end, kind: kind);

  @override
  Future<int> addTransaction(NewTransaction input) =>
      _dao.createWithBalanceUpdate(input);

  @override
  Future<void> updateTransaction(int txnId, NewTransaction input) =>
      _dao.updateWithBalanceAdjust(txnId, input);

  @override
  Future<void> deleteTransaction(int txnId) =>
      _dao.deleteWithBalanceReversal(txnId);
}
