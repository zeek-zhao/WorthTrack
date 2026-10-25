import 'package:flutter_test/flutter_test.dart';
import 'package:worthtrack/core/money.dart';

void main() {
  group('Money.parseYuan 元 → 分', () {
    test('整数元', () {
      expect(Money.parseYuan('12'), 1200);
      expect(Money.parseYuan('0'), 0);
    });

    test('一位小数补零', () {
      expect(Money.parseYuan('12.3'), 1230);
      expect(Money.parseYuan('0.1'), 10);
    });

    test('两位小数', () {
      expect(Money.parseYuan('12.34'), 1234);
      expect(Money.parseYuan('0.01'), 1);
    });

    test('首位零与前后空白', () {
      expect(Money.parseYuan('  07.5 '), 750);
    });

    test('大金额边界', () {
      expect(Money.parseYuan('99999999.99'), 9999999999);
    });

    test('非法输入抛 FormatException', () {
      expect(() => Money.parseYuan(''), throwsFormatException);
      expect(() => Money.parseYuan('abc'), throwsFormatException);
      expect(() => Money.parseYuan('-5'), throwsFormatException);
      expect(() => Money.parseYuan('12.345'), throwsFormatException);
      expect(() => Money.parseYuan('1,234'), throwsFormatException);
      expect(() => Money.parseYuan('1e3'), throwsFormatException);
      expect(() => Money.parseYuan('.5'), throwsFormatException);
      expect(() => Money.parseYuan('5.'), throwsFormatException);
    });

    test('tryParseYuan 非法输入返回 null', () {
      expect(Money.tryParseYuan('abc'), isNull);
      expect(Money.tryParseYuan(null), isNull);
      expect(Money.tryParseYuan('12.34'), 1234);
    });
  });

  group('Money.toYuan 分 → 元', () {
    test('常规转换恒定两位小数', () {
      expect(Money.toYuan(1234), '12.34');
      expect(Money.toYuan(1200), '12.00');
      expect(Money.toYuan(5), '0.05');
      expect(Money.toYuan(120), '1.20');
      expect(Money.toYuan(0), '0.00');
    });

    test('负数保留负号（信用卡余额）', () {
      expect(Money.toYuan(-1234), '-12.34');
    });

    test('toYuanSymbol 带货币符号', () {
      expect(Money.toYuanSymbol(123456), '¥1234.56');
    });

    test('往返一致性：parse(to(x)) == x', () {
      for (final minor in [0, 1, 5, 99, 100, 105, 1234, 9999999999]) {
        expect(
          Money.tryParseYuan(Money.toYuan(minor)),
          minor,
          reason: 'minor=$minor',
        );
      }
    });
  });
}
