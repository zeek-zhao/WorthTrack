import 'package:worthtrack/core/money.dart';
import 'package:worthtrack/data/db/app_database.dart';

/// 行情代码：市场前缀 + 6 位代码，如 `sh600519`、`sz159915`。
///
/// 价格缓存（price_cache.symbol）与后续行情接口（M3-#14）都以它为键。
String positionSymbol(Market market, String code) => '${market.name}$code';

/// 市场中文名（列表/详情展示）。
String marketLabel(Market market) => switch (market) {
  Market.sh => '沪',
  Market.sz => '深',
};

/// 份额（0.01 份为单位）→ 展示文本，如 15025 → "150.25"。
String formatShares(int sharesCent) => Money.toYuan(sharesCent);

/// 价格时间标注（M3-#15）：让用户一眼看出「这个市值是什么时候的价」。
///
/// - 当天：`价格更新 15:00`
/// - 当年其它日期：`价格更新 10-26 15:00`
/// - 跨年：`价格更新 2025-12-31 15:00`
///
/// [now] 仅用于测试注入，生产传 null 取本地当前时间。
String formatPriceTime(DateTime updatedAt, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final time =
      '${updatedAt.hour.toString().padLeft(2, '0')}:'
      '${updatedAt.minute.toString().padLeft(2, '0')}';
  if (updatedAt.year == current.year &&
      updatedAt.month == current.month &&
      updatedAt.day == current.day) {
    return '价格更新 $time';
  }
  final monthDay =
      '${updatedAt.month.toString().padLeft(2, '0')}-'
      '${updatedAt.day.toString().padLeft(2, '0')}';
  if (updatedAt.year == current.year) {
    return '价格更新 $monthDay $time';
  }
  return '价格更新 ${updatedAt.year}-$monthDay $time';
}

/// 解析份额输入（最多两位小数）→ 0.01 份整数；非法返回 null。
///
/// 份额与金额同为「两位小数定点数」，复用同一套校验规则。
int? tryParseSharesCent(String? input) => Money.tryParseYuan(input);

/// (a × b) ÷ 100，四舍五入到整数（远离零）。
///
/// 用于「份额（0.01 份）× 价格（分）」→ 金额（分）：
/// 15000（150.00 份）× 170000（1700.00 元）÷ 100 = 25500000 分。
int scaleByHundredths(int a, int b) {
  final product = a * b;
  final sign = product.isNegative ? -1 : 1;
  return sign * ((product.abs() + 50) ~/ 100);
}

/// 单条持仓的估值快照（issue #13）。
///
/// 全部整数运算，不引入浮点误差；仅在百分比处产生 double（展示用）。
class PositionValuation {
  const PositionValuation({
    required this.position,
    this.priceMinor,
    this.priceUpdatedAt,
  });

  final Position position;

  /// 现价（分）。null 表示还没录价（M3-#14 起由行情自动填充）。
  final int? priceMinor;

  /// 现价时间（手动改价或行情拉取时刻）。
  final DateTime? priceUpdatedAt;

  /// 行情代码，如 sh600519。
  String get symbol => positionSymbol(position.market, position.code);

  /// 成本金额（分）= 份额 × 成本价。
  int get costMinor =>
      scaleByHundredths(position.sharesCent, position.costPriceMinor);

  bool get hasPrice => priceMinor != null;

  /// 市值（分）= 份额 × 现价；无现价时为 null。
  int? get marketValueMinor {
    final price = priceMinor;
    return price == null ? null : scaleByHundredths(position.sharesCent, price);
  }

  /// 浮动盈亏（分）= 市值 − 成本；无现价时为 null。
  int? get profitMinor {
    final marketValue = marketValueMinor;
    return marketValue == null ? null : marketValue - costMinor;
  }

  /// 浮动盈亏百分比（12.34 表示 +12.34%）；无现价或成本为 0 时 null。
  double? get profitPercent {
    final profit = profitMinor;
    if (profit == null || costMinor == 0) return null;
    return profit / costMinor * 100;
  }
}

/// 持仓组合汇总（持仓页顶部卡片）。
///
/// 口径：市值与盈亏只统计**已有现价**的持仓；无价持仓单独计数提示，
/// 避免「市值少算几只」被误读成亏损。成本也只累加有价部分，
/// 保证 盈亏 = 市值 − 成本 自洽。
class PortfolioSummary {
  const PortfolioSummary({
    required this.marketValueMinor,
    required this.costMinor,
    required this.profitMinor,
    required this.profitPercent,
    required this.pricedCount,
    required this.unpricedCount,
    required this.totalCount,
  });

  final int marketValueMinor;
  final int costMinor;
  final int profitMinor;

  /// 盈亏百分比；无有价持仓或成本为 0 时为 null。
  final double? profitPercent;

  /// 已录价 / 未录价 / 全部 持仓数。
  final int pricedCount;
  final int unpricedCount;
  final int totalCount;

  bool get isEmpty => totalCount == 0;

  factory PortfolioSummary.from(List<PositionValuation> valuations) {
    var marketValue = 0;
    var cost = 0;
    var priced = 0;
    var unpriced = 0;
    for (final v in valuations) {
      final value = v.marketValueMinor;
      if (value == null) {
        unpriced++;
        continue;
      }
      priced++;
      marketValue += value;
      cost += v.costMinor;
    }
    final profit = marketValue - cost;
    return PortfolioSummary(
      marketValueMinor: marketValue,
      costMinor: cost,
      profitMinor: profit,
      profitPercent: cost == 0 ? null : profit / cost * 100,
      pricedCount: priced,
      unpricedCount: unpriced,
      totalCount: valuations.length,
    );
  }
}
