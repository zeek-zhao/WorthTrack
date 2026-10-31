/// 记事本的纯文本逻辑（可单测，不依赖 Flutter 与数据库）。
library;

/// 列表里显示什么标题。
///
/// 允许「只写正文不写标题」——随手记一句时逼用户起标题，等于把人劝退。
/// 这种情况退化显示正文首行，再退化为「（空笔记）」。
String noteDisplayTitle(String title, String body) {
  final trimmed = title.trim();
  if (trimmed.isNotEmpty) return trimmed;
  for (final line in body.split('\n')) {
    final text = line.trim();
    if (text.isNotEmpty) return text;
  }
  return '（空笔记）';
}

/// 列表副标题：最近修改时间。
///
/// 分四档而不是一律 `yyyy-MM-dd`：刚写的笔记看「今天 14:32」比看完整日期有用得多，
/// 越久远的才需要越来越精确的日期。
String formatNoteTime(DateTime at, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final day = DateTime(at.year, at.month, at.day);
  final today = DateTime(current.year, current.month, current.day);
  final clock = '${_two(at.hour)}:${_two(at.minute)}';

  final diffDays = today.difference(day).inDays;
  if (diffDays == 0) return '今天 $clock';
  if (diffDays == 1) return '昨天 $clock';
  if (at.year == current.year) return '${at.month}月${at.day}日';
  return '${at.year}年${at.month}月${at.day}日';
}

String _two(int value) => value.toString().padLeft(2, '0');

/// 关键词是否命中这条笔记（标题 + 正文，大小写不敏感）。
///
/// **刻意不用 SQL 的 `LIKE`**，两个原因：
/// 1. `LIKE` 里的 `%` 和 `_` 是通配符，用户搜「50%」会搜出一堆无关笔记；
/// 2. SQLite 的 `LIKE` 只对 ASCII 大小写不敏感，行为与用户预期不一致。
///
/// 笔记是个人量级（几百条），在 Dart 端过滤完全够用，且逻辑可单测。
bool noteMatchesKeyword(String title, String body, String keyword) {
  final needle = keyword.trim().toLowerCase();
  if (needle.isEmpty) return true;
  return title.toLowerCase().contains(needle) ||
      body.toLowerCase().contains(needle);
}
