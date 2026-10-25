import 'package:drift/drift.dart';

import '../db/app_database.dart';

part 'budget_dao.g.dart';

/// 月度预算 DAO（issue #10）。
@DriftAccessor(tables: [Budgets, Categories])
class BudgetDao extends DatabaseAccessor<AppDatabase> with _$BudgetDaoMixin {
  BudgetDao(super.db);

  /// 监听指定月份的预算及其分类（按分类排序），供报表页/预算页展示。
  Stream<List<(Budget, Category)>> watchBudgetsWithCategory(DateTime month) {
    final start = DateTime(month.year, month.month);
    final query = select(budgets).join([
      innerJoin(categories, categories.id.equalsExp(budgets.categoryId)),
    ]);
    query.where(
      budgets.month.isBiggerOrEqualValue(start) &
          budgets.month.isSmallerThanValue(
            DateTime(month.year, month.month + 1),
          ),
    );
    query.orderBy([
      OrderingTerm.asc(categories.sortOrder),
      OrderingTerm.asc(categories.id),
    ]);
    return query.watch().map(
      (rows) => rows
          .map((r) => (r.readTable(budgets), r.readTable(categories)))
          .toList(),
    );
  }

  /// 查询单条预算（月份归一化到当月 1 日）。
  Future<Budget?> getByCategoryAndMonth(int categoryId, DateTime month) {
    final m = DateTime(month.year, month.month);
    return (select(budgets)
          ..where((b) => b.categoryId.equals(categoryId) & b.month.equals(m)))
        .getSingleOrNull();
  }

  /// 设置/更新某分类某月预算（唯一键 categoryId+month，幂等 upsert）。
  Future<void> upsert(
    DateTime month, {
    required int categoryId,
    required int amountMinor,
  }) {
    final m = DateTime(month.year, month.month);
    return attachedDatabase.transaction(() async {
      final existing = await getByCategoryAndMonth(categoryId, m);
      if (existing == null) {
        await into(budgets).insert(
          BudgetsCompanion.insert(
            categoryId: categoryId,
            amountMinor: amountMinor,
            month: m,
          ),
        );
      } else {
        await (update(budgets)..where((b) => b.id.equals(existing.id))).write(
          BudgetsCompanion(amountMinor: Value(amountMinor)),
        );
      }
    });
  }

  /// 删除预算。
  Future<void> deleteBudget(int id) {
    return (delete(budgets)..where((b) => b.id.equals(id))).go();
  }
}
