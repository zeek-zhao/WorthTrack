import 'package:drift/drift.dart';

import 'package:worthtrack/data/db/app_database.dart';

part 'recurring_dao.g.dart';

/// 周期账单规则 DAO（issue #11）。
@DriftAccessor(tables: [RecurringRules])
class RecurringDao extends DatabaseAccessor<AppDatabase>
    with _$RecurringDaoMixin {
  RecurringDao(super.db);

  /// 监听规则（默认仅启用中的，按下次执行时间排序）。
  Stream<List<RecurringRule>> watchRules({bool includeInactive = false}) {
    final query = select(recurringRules);
    if (!includeInactive) {
      query.where((r) => r.active.equals(true));
    }
    query.orderBy([
      (r) => OrderingTerm.asc(r.nextRunAt),
      (r) => OrderingTerm.asc(r.id),
    ]);
    return query.watch();
  }

  Future<RecurringRule?> getById(int id) {
    return (select(
      recurringRules,
    )..where((r) => r.id.equals(id))).getSingleOrNull();
  }

  /// 到期待补生成的启用规则（nextRunAt <= now）。
  Future<List<RecurringRule>> dueRules(DateTime now) {
    return (select(recurringRules)
          ..where(
            (r) =>
                r.active.equals(true) & r.nextRunAt.isSmallerOrEqualValue(now),
          )
          ..orderBy([(r) => OrderingTerm.asc(r.nextRunAt)]))
        .get();
  }

  Future<int> createRule(RecurringRulesCompanion entry) {
    return into(recurringRules).insert(entry);
  }

  Future<void> updateRule(int id, RecurringRulesCompanion entry) {
    return (update(recurringRules)..where((r) => r.id.equals(id))).write(entry);
  }

  Future<void> deleteRule(int id) {
    return (delete(recurringRules)..where((r) => r.id.equals(id))).go();
  }
}
