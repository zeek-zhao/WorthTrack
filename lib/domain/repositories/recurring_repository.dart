import '../../../data/db/app_database.dart';

/// 周期账单领域接口（issue #11）。
abstract class RecurringRepository {
  /// 监听规则列表（默认仅启用中）。
  Stream<List<RecurringRule>> watchRules({bool includeInactive});

  /// 新建规则，返回 id。周期账单不支持转账类型。
  Future<int> addRule({
    required String name,
    required TxnType type,
    required int accountId,
    int? categoryId,
    required int amountMinor,
    required RecurFrequency frequency,
    int interval,
    required DateTime startDate,
    DateTime? endDate,
    String? note,
  });

  /// 编辑规则基础字段。
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
  });

  /// 删除规则（不回滚已生成的交易）。
  Future<void> deleteRule(int id);

  /// 启用/停用规则。
  Future<void> setActive(int id, bool active);

  /// 启动补生成：把所有到期规则从 nextRunAt 推进到 [now]，
  /// 逐期生成交易并调整余额，返回生成笔数。幂等（重复调用不再生成）。
  /// 规则越过 endDate 时自动停用。
  Future<int> catchUp(DateTime now);
}
