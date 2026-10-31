import 'package:worthtrack/core/stream_utils.dart';
import 'package:worthtrack/domain/repositories/budget_repository.dart';
import 'package:worthtrack/domain/stats.dart';
import 'package:worthtrack/data/dao/budget_dao.dart';
import 'package:worthtrack/data/dao/transaction_dao.dart';
import 'package:worthtrack/data/db/app_database.dart';

/// [BudgetRepository] 的 Drift 实现：
/// 预算流 × 当月分类支出流 → 消耗状态流（Dart 端组合）。
class BudgetRepositoryImpl implements BudgetRepository {
  BudgetRepositoryImpl(this._budgetDao, this._txnDao);

  final BudgetDao _budgetDao;
  final TransactionDao _txnDao;

  @override
  Stream<List<BudgetStatus>> watchBudgetStatuses(DateTime month) {
    return combineLatest2(
      _budgetDao.watchBudgetsWithCategory(month),
      _txnDao.watchCategoryStats(month, kind: CategoryKind.expense),
      (rows, stats) {
        final spentBy = <int, int>{
          for (final s in stats)
            if (s.categoryId != null) s.categoryId!: s.totalMinor,
        };
        return rows
            .map(
              (r) => BudgetStatus(
                budget: r.$1,
                category: r.$2,
                spentMinor: spentBy[r.$1.categoryId] ?? 0,
              ),
            )
            .toList();
      },
    );
  }

  @override
  Future<void> upsertBudget(
    DateTime month, {
    required int categoryId,
    required int amountMinor,
  }) => _budgetDao.upsert(
    month,
    categoryId: categoryId,
    amountMinor: amountMinor,
  );

  @override
  Future<void> deleteBudget(int id) => _budgetDao.deleteBudget(id);
}
