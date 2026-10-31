import 'package:worthtrack/data/db/app_database.dart';

/// 周期账单推进结果（纯函数计算，不碰数据库）。
class RecurringSchedule {
  const RecurringSchedule({
    required this.dueDates,
    required this.nextRunAt,
    required this.ended,
  });

  /// 从 [RecurringScheduleInput.from] 到 [RecurringScheduleInput.until]（含两端）
  /// 的全部到期时间点，按时间升序。「连漏 N 期只生成 N 期」由此保证。
  final List<DateTime> dueDates;

  /// 下一次未到期的发生时间（> until，且未越过 endDate 时为有效下次执行时间）。
  final DateTime nextRunAt;

  /// nextRunAt 已越过 endDate，规则应停用。
  final bool ended;
}

/// [advanceSchedule] 的参数包。
class RecurringScheduleInput {
  const RecurringScheduleInput({
    required this.frequency,
    required this.interval,
    required this.from,
    required this.until,
    this.endDate,
  });

  final RecurFrequency frequency;
  final int interval;

  /// 起算点（通常是规则的 nextRunAt / startDate），该时点本身计入结果。
  final DateTime from;

  /// 推进上限（通常是当前时间），含当天。
  final DateTime until;

  /// 规则结束时间，null 表示无限。
  final DateTime? endDate;
}

/// 由 [input.from] 向后逐期推进到 [input.until]，收集全部到期时间。
///
/// - 纯函数：无 IO、无时钟读取，便于单测
/// - 迭代上限 1000 期，异常数据（如超小间隔）不会死循环
RecurringSchedule advanceSchedule(RecurringScheduleInput input) {
  assert(input.interval >= 1, 'interval 必须 ≥ 1');
  final due = <DateTime>[];
  var cur = input.from;
  var guard = 0;
  while (!cur.isAfter(input.until)) {
    if (input.endDate != null && cur.isAfter(input.endDate!)) {
      break;
    }
    due.add(cur);
    cur = _advanceOne(cur, input.frequency, input.interval);
    if (++guard > 1000) {
      break;
    }
  }
  final ended = input.endDate != null && cur.isAfter(input.endDate!);
  return RecurringSchedule(dueDates: due, nextRunAt: cur, ended: ended);
}

DateTime _advanceOne(DateTime t, RecurFrequency f, int interval) => switch (f) {
  RecurFrequency.daily => t.add(Duration(days: interval)),
  RecurFrequency.weekly => t.add(Duration(days: 7 * interval)),
  RecurFrequency.monthly => addMonths(t, interval),
  RecurFrequency.yearly => addMonths(t, 12 * interval),
};

/// 加 N 个月，日超出目标月天数时收敛到当月最后一天
/// （收敛日随传导延续：1-31 → 2-28 → 3-28，日期算术语义）。
/// 年度加 12N 个月，2-29 → 次年 2-28。
DateTime addMonths(DateTime t, int months) {
  final total = t.month - 1 + months;
  final y = t.year + total ~/ 12;
  final m = total % 12 + 1;
  final lastDay = DateTime(y, m + 1, 0).day;
  final day = t.day > lastDay ? lastDay : t.day;
  return DateTime(
    y,
    m,
    day,
    t.hour,
    t.minute,
    t.second,
    t.millisecond,
    t.microsecond,
  );
}

/// 周期频率的中文标签。
String frequencyLabel(RecurFrequency f) => switch (f) {
  RecurFrequency.daily => '每天',
  RecurFrequency.weekly => '每周',
  RecurFrequency.monthly => '每月',
  RecurFrequency.yearly => '每年',
};
