import 'package:drift/drift.dart';

import 'package:worthtrack/domain/recurring_logic.dart';
import 'package:worthtrack/domain/repositories/recurring_repository.dart';
import 'package:worthtrack/data/dao/recurring_dao.dart';
import 'package:worthtrack/data/dao/transaction_dao.dart';
import 'package:worthtrack/data/db/app_database.dart';

/// [RecurringRepository] 的 Drift 实现。
///
/// 补生成逻辑：到期规则由 [advanceSchedule]（纯函数）算出到期时间，
/// 每期生成一笔交易并同步调整余额（复用碰钱路径的事务）。
class RecurringRepositoryImpl implements RecurringRepository {
  RecurringRepositoryImpl(this._dao, this._txnDao);

  final RecurringDao _dao;
  final TransactionDao _txnDao;

  @override
  Stream<List<RecurringRule>> watchRules({bool includeInactive = false}) =>
      _dao.watchRules(includeInactive: includeInactive);

  @override
  Future<int> addRule({
    required String name,
    required TxnType type,
    required int accountId,
    int? categoryId,
    required int amountMinor,
    required RecurFrequency frequency,
    int interval = 1,
    required DateTime startDate,
    DateTime? endDate,
    String? note,
  }) {
    if (type == TxnType.transfer) {
      throw ArgumentError('周期账单不支持转账类型');
    }
    if (interval < 1) {
      throw ArgumentError('间隔必须 ≥ 1');
    }
    return _dao.createRule(
      RecurringRulesCompanion.insert(
        name: name,
        type: type,
        accountId: accountId,
        amountMinor: amountMinor,
        frequency: frequency,
        startDate: startDate,
        nextRunAt: startDate,
        interval: Value(interval),
        categoryId: Value(categoryId),
        endDate: Value(endDate),
        note: Value(note),
      ),
    );
  }

  @override
  Future<void> updateRule({
    required int id,
    String? name,
    int? accountId,
    int? categoryId,
    int? amountMinor,
    RecurFrequency? frequency,
    int? interval,
    DateTime? endDate,
    String? note,
  }) {
    return _dao.updateRule(
      id,
      RecurringRulesCompanion(
        name: name == null ? const Value.absent() : Value(name),
        accountId: accountId == null ? const Value.absent() : Value(accountId),
        categoryId: categoryId == null
            ? const Value.absent()
            : Value(categoryId),
        amountMinor: amountMinor == null
            ? const Value.absent()
            : Value(amountMinor),
        frequency: frequency == null ? const Value.absent() : Value(frequency),
        interval: interval == null ? const Value.absent() : Value(interval),
        endDate: Value(endDate),
        note: note == null ? const Value.absent() : Value(note),
      ),
    );
  }

  @override
  Future<void> deleteRule(int id) => _dao.deleteRule(id);

  @override
  Future<void> setActive(int id, bool active) =>
      _dao.updateRule(id, RecurringRulesCompanion(active: Value(active)));

  @override
  Future<int> catchUp(DateTime now) {
    return _dao.attachedDatabase.transaction(() async {
      var generated = 0;
      final rules = await _dao.dueRules(now);
      for (final rule in rules) {
        final schedule = advanceSchedule(
          RecurringScheduleInput(
            frequency: rule.frequency,
            interval: rule.interval,
            from: rule.nextRunAt,
            until: now,
            endDate: rule.endDate,
          ),
        );
        for (final at in schedule.dueDates) {
          await _txnDao.createWithBalanceUpdate(
            NewTransaction(
              type: rule.type,
              accountId: rule.accountId,
              categoryId: rule.categoryId,
              amountMinor: rule.amountMinor,
              note: rule.note ?? '周期账单：${rule.name}',
              occurredAt: at,
            ),
          );
          generated++;
        }
        if (schedule.ended) {
          await _dao.updateRule(
            rule.id,
            RecurringRulesCompanion(active: const Value(false)),
          );
        } else if (schedule.dueDates.isNotEmpty ||
            schedule.nextRunAt.isAfter(rule.nextRunAt)) {
          await _dao.updateRule(
            rule.id,
            RecurringRulesCompanion(nextRunAt: Value(schedule.nextRunAt)),
          );
        }
      }
      return generated;
    });
  }
}
