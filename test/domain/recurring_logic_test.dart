import 'package:flutter_test/flutter_test.dart';
import 'package:worthtrack/data/db/app_database.dart';
import 'package:worthtrack/modules/finance/domain/recurring_logic.dart';

/// issue #11 验收：周期推进纯函数测试（连漏 N 期只生成 N 期、月末收敛、endDate 截断）。
void main() {
  group('月度', () {
    test('连漏三期只生成三期，nextRun 落到下一期', () {
      final s = advanceSchedule(
        RecurringScheduleInput(
          frequency: RecurFrequency.monthly,
          interval: 1,
          from: DateTime(2026, 7, 10),
          until: DateTime(2026, 10, 5, 12),
        ),
      );
      expect(s.dueDates, [
        DateTime(2026, 7, 10),
        DateTime(2026, 8, 10),
        DateTime(2026, 9, 10),
      ]);
      expect(s.nextRunAt, DateTime(2026, 10, 10));
      expect(s.ended, isFalse);
    });

    test('幂等：以推进后的 nextRun 再跑一次，不再生成', () {
      final first = advanceSchedule(
        RecurringScheduleInput(
          frequency: RecurFrequency.monthly,
          interval: 1,
          from: DateTime(2026, 7, 10),
          until: DateTime(2026, 10, 5, 12),
        ),
      );
      final second = advanceSchedule(
        RecurringScheduleInput(
          frequency: RecurFrequency.monthly,
          interval: 1,
          from: first.nextRunAt,
          until: DateTime(2026, 10, 5, 12),
        ),
      );
      expect(second.dueDates, isEmpty);
      expect(second.nextRunAt, first.nextRunAt);
    });

    test('当期已到（until == 发生日）时计入', () {
      final s = advanceSchedule(
        RecurringScheduleInput(
          frequency: RecurFrequency.monthly,
          interval: 1,
          from: DateTime(2026, 7, 10),
          until: DateTime(2026, 10, 10, 8),
        ),
      );
      expect(s.dueDates, hasLength(4));
      expect(s.dueDates.last, DateTime(2026, 10, 10));
      expect(s.nextRunAt, DateTime(2026, 11, 10));
    });

    test('每 3 个月一次', () {
      final s = advanceSchedule(
        RecurringScheduleInput(
          frequency: RecurFrequency.monthly,
          interval: 3,
          from: DateTime(2026, 1, 10),
          until: DateTime(2026, 10, 5),
        ),
      );
      expect(s.dueDates, [
        DateTime(2026, 1, 10),
        DateTime(2026, 4, 10),
        DateTime(2026, 7, 10),
      ]);
      expect(s.nextRunAt, DateTime(2026, 10, 10));
    });

    test('月末日期收敛：1-31 → 2-28 → 3-28（日期算术传导）', () {
      final s = advanceSchedule(
        RecurringScheduleInput(
          frequency: RecurFrequency.monthly,
          interval: 1,
          from: DateTime(2026, 1, 31),
          until: DateTime(2026, 4, 1),
        ),
      );
      expect(s.dueDates, [
        DateTime(2026, 1, 31),
        DateTime(2026, 2, 28),
        DateTime(2026, 3, 28),
      ]);
      expect(s.nextRunAt, DateTime(2026, 4, 28));
    });
  });

  group('每日/每周', () {
    test('每 2 天一次', () {
      final s = advanceSchedule(
        RecurringScheduleInput(
          frequency: RecurFrequency.daily,
          interval: 2,
          from: DateTime(2026, 10, 1),
          until: DateTime(2026, 10, 6),
        ),
      );
      expect(s.dueDates, [
        DateTime(2026, 10, 1),
        DateTime(2026, 10, 3),
        DateTime(2026, 10, 5),
      ]);
      expect(s.nextRunAt, DateTime(2026, 10, 7));
    });

    test('每周一次跨月', () {
      final s = advanceSchedule(
        RecurringScheduleInput(
          frequency: RecurFrequency.weekly,
          interval: 1,
          from: DateTime(2026, 1, 26),
          until: DateTime(2026, 2, 20),
        ),
      );
      expect(s.dueDates, [
        DateTime(2026, 1, 26),
        DateTime(2026, 2, 2),
        DateTime(2026, 2, 9),
        DateTime(2026, 2, 16),
      ]);
      expect(s.nextRunAt, DateTime(2026, 2, 23));
    });
  });

  group('每年', () {
    test('2-29 年度收敛到 2-28', () {
      final s = advanceSchedule(
        RecurringScheduleInput(
          frequency: RecurFrequency.yearly,
          interval: 1,
          from: DateTime(2024, 2, 29),
          until: DateTime(2026, 3, 1),
        ),
      );
      expect(s.dueDates, [
        DateTime(2024, 2, 29),
        DateTime(2025, 2, 28),
        DateTime(2026, 2, 28),
      ]);
      expect(s.nextRunAt, DateTime(2027, 2, 28));
    });
  });

  group('endDate 截断', () {
    test('越过 endDate 停止并标记 ended', () {
      final s = advanceSchedule(
        RecurringScheduleInput(
          frequency: RecurFrequency.monthly,
          interval: 1,
          from: DateTime(2026, 1, 1),
          until: DateTime(2026, 12, 31),
          endDate: DateTime(2026, 2, 15),
        ),
      );
      expect(s.dueDates, [DateTime(2026, 1, 1), DateTime(2026, 2, 1)]);
      expect(s.ended, isTrue);
    });

    test('from 已越过 endDate：空结果且 ended', () {
      final s = advanceSchedule(
        RecurringScheduleInput(
          frequency: RecurFrequency.monthly,
          interval: 1,
          from: DateTime(2026, 3, 1),
          until: DateTime(2026, 12, 31),
          endDate: DateTime(2026, 2, 15),
        ),
      );
      expect(s.dueDates, isEmpty);
      expect(s.ended, isTrue);
    });
  });

  test('from 晚于 until：空结果', () {
    final s = advanceSchedule(
      RecurringScheduleInput(
        frequency: RecurFrequency.daily,
        interval: 1,
        from: DateTime(2026, 10, 10),
        until: DateTime(2026, 10, 5),
      ),
    );
    expect(s.dueDates, isEmpty);
    expect(s.nextRunAt, DateTime(2026, 10, 10));
    expect(s.ended, isFalse);
  });

  test('addMonths 保留时刻', () {
    final t = addMonths(DateTime(2026, 1, 31, 9, 30), 1);
    expect(t, DateTime(2026, 2, 28, 9, 30));
  });
}
