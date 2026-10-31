import 'package:flutter_test/flutter_test.dart';
import 'package:worthtrack/modules/notes/domain/note_text.dart';

/// issue #47：记事本的纯文本逻辑。
void main() {
  group('noteDisplayTitle', () {
    test('有标题就用标题，并去掉首尾空白', () {
      expect(noteDisplayTitle('  买菜  ', '正文'), '买菜');
    });

    test('标题为空时退化显示正文首行（跳过空行）', () {
      expect(noteDisplayTitle('', '\n\n  今晚想想这个  \n细节'), '今晚想想这个');
      expect(noteDisplayTitle('   ', '正文第一行'), '正文第一行');
    });

    test('标题与正文都空时给出明确占位，而不是空字符串', () {
      expect(noteDisplayTitle('', ''), '（空笔记）');
      expect(noteDisplayTitle('', '   \n  '), '（空笔记）');
    });
  });

  group('formatNoteTime', () {
    final now = DateTime(2026, 10, 31, 20, 5);

    test('当天显示「今天 时:分」', () {
      expect(
        formatNoteTime(DateTime(2026, 10, 31, 9, 3), now: now),
        '今天 09:03',
      );
      expect(
        formatNoteTime(DateTime(2026, 10, 31, 20, 5), now: now),
        '今天 20:05',
      );
    });

    test('前一天显示「昨天 时:分」', () {
      expect(
        formatNoteTime(DateTime(2026, 10, 30, 23, 59), now: now),
        '昨天 23:59',
      );
    });

    test('今年更早的日期显示月日', () {
      expect(formatNoteTime(DateTime(2026, 3, 7, 10), now: now), '3月7日');
    });

    test('跨年显示完整年月日', () {
      expect(
        formatNoteTime(DateTime(2025, 12, 31, 10), now: now),
        '2025年12月31日',
      );
    });

    test('「昨天」按日历日算，不是按 24 小时算', () {
      // 今天 00:05 与昨天 23:55 只差 10 分钟，但跨了日历日，应显示「昨天」。
      final earlyToday = DateTime(2026, 10, 31, 0, 5);
      expect(
        formatNoteTime(DateTime(2026, 10, 30, 23, 55), now: earlyToday),
        '昨天 23:55',
      );
    });
  });
  group('noteMatchesKeyword', () {
    test('空关键词（含纯空白）一律命中', () {
      expect(noteMatchesKeyword('标题', '正文', ''), isTrue);
      expect(noteMatchesKeyword('标题', '正文', '   '), isTrue);
    });

    test('标题与正文都能命中', () {
      expect(noteMatchesKeyword('买菜的清单', '正文', '买菜'), isTrue);
      expect(noteMatchesKeyword('标题', '顺便记一下买菜', '买菜'), isTrue);
    });

    test('大小写不敏感（Dart 端处理，不依赖 SQLite 的 ASCII 限制）', () {
      expect(noteMatchesKeyword('ETF 复盘', '', 'etf'), isTrue);
      expect(noteMatchesKeyword('标题', 'Net Worth 口径', 'net worth'), isTrue);
    });

    test('关键词首尾空白被忽略', () {
      expect(noteMatchesKeyword('买菜', '', '  买菜  '), isTrue);
    });

    test('% 与 _ 是普通字符，不是通配符', () {
      // 这正是放弃 SQL LIKE 的原因：LIKE 里搜 "50%" 会匹配任意内容。
      expect(noteMatchesKeyword('仓位 50% 上限', '', '50%'), isTrue);
      expect(noteMatchesKeyword('仓位 5000 上限', '', '50%'), isFalse);
      expect(noteMatchesKeyword('a_b', '', 'a_b'), isTrue);
      expect(noteMatchesKeyword('axb', '', 'a_b'), isFalse);
    });

    test('都不命中时返回 false', () {
      expect(noteMatchesKeyword('买菜', '清单', '股票'), isFalse);
    });
  });
}
