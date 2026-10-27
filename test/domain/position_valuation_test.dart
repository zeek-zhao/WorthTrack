import 'package:flutter_test/flutter_test.dart';
import 'package:worthtrack/data/db/app_database.dart';
import 'package:worthtrack/domain/position_valuation.dart';

/// issue #13 验收：市值 / 盈亏 / 百分比计算单测（纯函数，不碰数据库）。
void main() {
  Position position({
    int id = 1,
    Market market = Market.sh,
    String code = '600519',
    String name = '贵州茅台',
    int sharesCent = 15000,
    int costPriceMinor = 160000,
  }) => Position(
    id: id,
    market: market,
    code: code,
    name: name,
    sharesCent: sharesCent,
    costPriceMinor: costPriceMinor,
    archivedAt: null,
    createdAt: DateTime(2026, 10, 27),
  );

  group('市值 / 成本 / 盈亏', () {
    test(
      '150.00 份 @成本 1600.00，现价 1700.00 → 市值 255000.00，盈亏 +15000.00（+6.25%）',
      () {
        final v = PositionValuation(position: position(), priceMinor: 170000);

        expect(v.costMinor, 24000000); // 150 × 1600 元 = 240000.00
        expect(v.marketValueMinor, 25500000); // 150 × 1700 元
        expect(v.profitMinor, 1500000); // +15000.00
        expect(v.profitPercent, closeTo(6.25, 1e-9));
      },
    );

    test('下跌：现价 1500.00 → 市值 225000.00，盈亏 -15000.00（-6.25%）', () {
      final v = PositionValuation(position: position(), priceMinor: 150000);

      expect(v.marketValueMinor, 22500000);
      expect(v.profitMinor, -1500000);
      expect(v.profitPercent, closeTo(-6.25, 1e-9));
    });

    test('场内基金份额与低价：1000.00 份 @成本 12.34，现价 13.00', () {
      final v = PositionValuation(
        position: position(
          market: Market.sz,
          code: '159915',
          name: '创业板ETF',
          sharesCent: 100000,
          costPriceMinor: 1234,
        ),
        priceMinor: 1300,
      );

      expect(v.costMinor, 1234000); // 1000 × 12.34 元 = 12340.00
      expect(v.marketValueMinor, 1300000); // 1000 × 13.00 元
      expect(v.profitMinor, 66000); // +660.00
      expect(v.profitPercent, closeTo(66000 / 1234000 * 100, 1e-9));
    });

    test('无现价：市值/盈亏/百分比全为 null', () {
      final v = PositionValuation(position: position());

      expect(v.hasPrice, isFalse);
      expect(v.marketValueMinor, isNull);
      expect(v.profitMinor, isNull);
      expect(v.profitPercent, isNull);
      // 成本不依赖现价，仍可算。
      expect(v.costMinor, 24000000);
    });

    test('零成本（送股/继承）：盈亏 = 市值，百分比为 null（避免除零）', () {
      final v = PositionValuation(
        position: position(sharesCent: 10000, costPriceMinor: 0),
        priceMinor: 5000,
      );

      expect(v.costMinor, 0);
      expect(v.marketValueMinor, 500000);
      expect(v.profitMinor, 500000);
      expect(v.profitPercent, isNull);
    });
  });

  group('整数运算与四舍五入', () {
    test('scaleByHundredths 向下/向上取整', () {
      // 3.33 份 × 12.34 元 = 41.0922 元 → 4109 分
      expect(scaleByHundredths(333, 1234), 4109);
      // 3.33 份 × 12.35 元 = 41.1255 元 → 4113 分
      expect(scaleByHundredths(333, 1235), 4113);
      // 恰好 .5 分进位（远离零）
      expect(scaleByHundredths(1, 150), 2);
      // 负向对称
      expect(scaleByHundredths(-333, 1234), -4109);
    });

    test('小数份额不产生浮点误差：0.07 份 × 3.33 元', () {
      // 7 × 333 = 2331 → 23.31 分 → 23 分
      expect(scaleByHundredths(7, 333), 23);
      final v = PositionValuation(
        position: position(sharesCent: 7, costPriceMinor: 333),
        priceMinor: 333,
      );
      expect(v.costMinor, 23);
      expect(v.marketValueMinor, 23);
      expect(v.profitMinor, 0);
      expect(v.profitPercent, 0);
    });
  });

  group('行情代码与份额格式', () {
    test('positionSymbol 拼接市场前缀', () {
      expect(positionSymbol(Market.sh, '600519'), 'sh600519');
      expect(positionSymbol(Market.sz, '159915'), 'sz159915');
    });

    test('marketLabel 中文名', () {
      expect(marketLabel(Market.sh), '沪');
      expect(marketLabel(Market.sz), '深');
    });

    test('formatShares 固定两位小数', () {
      expect(formatShares(15000), '150.00');
      expect(formatShares(15025), '150.25');
      expect(formatShares(7), '0.07');
    });

    test('tryParseSharesCent 解析与非法输入', () {
      expect(tryParseSharesCent('150'), 15000);
      expect(tryParseSharesCent('150.2'), 15020);
      expect(tryParseSharesCent('150.25'), 15025);
      expect(tryParseSharesCent('0.07'), 7);
      expect(tryParseSharesCent(''), isNull);
      expect(tryParseSharesCent('150.256'), isNull);
      expect(tryParseSharesCent('abc'), isNull);
      expect(tryParseSharesCent('-1'), isNull);
    });
  });

  group('组合汇总', () {
    test('空组合', () {
      final s = PortfolioSummary.from(const []);

      expect(s.isEmpty, isTrue);
      expect(s.marketValueMinor, 0);
      expect(s.costMinor, 0);
      expect(s.profitMinor, 0);
      expect(s.profitPercent, isNull);
      expect(s.totalCount, 0);
    });

    test('无价持仓不计入市值，成本与盈亏口径自洽', () {
      final s = PortfolioSummary.from([
        PositionValuation(position: position(), priceMinor: 170000),
        PositionValuation(
          position: position(id: 2, code: '000001', name: '平安银行'),
        ),
      ]);

      expect(s.totalCount, 2);
      expect(s.pricedCount, 1);
      expect(s.unpricedCount, 1);
      expect(s.marketValueMinor, 25500000);
      // 只累加有价持仓的成本，保证 盈亏 = 市值 − 成本。
      expect(s.costMinor, 24000000);
      expect(s.profitMinor, 1500000);
      expect(s.profitPercent, closeTo(6.25, 1e-9));
    });

    test('多只有价持仓累加', () {
      final s = PortfolioSummary.from([
        PositionValuation(position: position(), priceMinor: 170000),
        PositionValuation(
          position: position(
            id: 2,
            market: Market.sz,
            code: '159915',
            name: '创业板ETF',
            sharesCent: 100000,
            costPriceMinor: 1234,
          ),
          priceMinor: 1300,
        ),
      ]);

      expect(s.pricedCount, 2);
      expect(s.unpricedCount, 0);
      expect(s.marketValueMinor, 25500000 + 1300000);
      expect(s.costMinor, 24000000 + 1234000);
      expect(s.profitMinor, 1500000 + 66000);
    });

    test('全部无价：市值 0，百分比 null，不影响「有价数量」判断', () {
      final s = PortfolioSummary.from([
        PositionValuation(position: position()),
        PositionValuation(position: position(id: 2, code: '000001')),
      ]);

      expect(s.pricedCount, 0);
      expect(s.unpricedCount, 2);
      expect(s.marketValueMinor, 0);
      expect(s.costMinor, 0);
      expect(s.profitPercent, isNull);
    });
  });
}
