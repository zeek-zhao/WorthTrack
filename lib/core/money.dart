/// 金额工具：全部金额以「分」（minor unit）整数存储，杜绝浮点误差。
///
/// 存储约定：
/// - 账户余额、交易金额、预算额度、成本/市价 → 分（1 元 = 100 分）
/// - 基金/股票份额 → 0.01 份（sharesCent），同样为整数
library;

class Money {
  Money._();

  /// 解析用户输入的元金额为分，非法输入抛 [FormatException]。
  ///
  /// 规则：
  /// - 允许 `12`、`12.3`、`12.34`；最多两位小数
  /// - 不允许空串、负数、科学计数、千分位逗号
  static int parseYuan(String yuan) {
    final value = tryParseYuan(yuan);
    if (value == null) {
      throw FormatException('无效金额: "$yuan"');
    }
    return value;
  }

  /// 安全解析，非法输入返回 null。
  static int? tryParseYuan(String? yuan) {
    if (yuan == null) return null;
    final s = yuan.trim();
    if (s.isEmpty) return null;
    // 只允许数字和至多一个小数点，且小数点后最多两位
    final match = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$').firstMatch(s);
    if (match == null) return null;
    final yuanPart = int.parse(match.group(1)!);
    final frac = match.group(2) ?? '';
    final fracMinor = int.parse(frac.padRight(2, '0'));
    return yuanPart * 100 + fracMinor;
  }

  /// 分 → 元字符串，恒定两位小数（展示用）。
  /// 例：1234 → "12.34"，5 → "0.05"，0 → "0.00"。
  static String toYuan(int minor) {
    final negative = minor < 0;
    final abs = minor.abs();
    final yuan = abs ~/ 100;
    final frac = abs % 100;
    final sign = negative ? '-' : '';
    return '$sign$yuan.${frac.toString().padLeft(2, '0')}';
  }

  /// 分 → 带 ¥ 符号的展示文本。
  /// 例：123456 → "¥1234.56"。
  static String toYuanSymbol(int minor) => '¥${toYuan(minor)}';
}
