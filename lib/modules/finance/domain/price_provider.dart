/// 行情（报价）领域接口与模型（issue #14）。
///
/// 边界：只覆盖 A 股与场内基金（沪/深），数据源为公开接口、无 key。
/// 具体实现在 `lib/data/price/`，通过 [PriceProvider] 抽象注入，
/// 后续换新浪/加备用源不影响上层。
library;

/// 单只证券的报价状态。
enum QuoteStatus {
  /// 有有效报价，可写入价格缓存。
  ok,

  /// 停牌 / 无成交（接口返回 0 或空价）：不覆盖已有缓存价。
  suspended,

  /// 代码不存在（接口无此代码）：不覆盖已有缓存价。
  notFound,
}

/// 单只证券的报价。
class Quote {
  const Quote({
    required this.symbol,
    required this.status,
    this.priceMinor,
    this.quotedAt,
  });

  /// 行情代码，如 sh600519。
  final String symbol;
  final QuoteStatus status;

  /// 现价（分）。仅 [QuoteStatus.ok] 时有值。
  final int? priceMinor;

  /// 行情时间（交易所侧时间）；接口未给出时为 null。
  final DateTime? quotedAt;

  @override
  String toString() => 'Quote($symbol, $status, $priceMinor, $quotedAt)';
}

/// 行情接口抽象。
abstract class PriceProvider {
  /// 批量拉取报价，返回以 symbol 为键的映射。
  ///
  /// 请求了但响应里缺失的 symbol 记为 [QuoteStatus.notFound]；
  /// 网络/HTTP 异常抛 [PriceFetchException]，由调用方决定兜底策略。
  Future<Map<String, Quote>> fetchQuotes(List<String> symbols);
}

/// 行情拉取失败（网络异常或 HTTP 状态码非 200）。
class PriceFetchException implements Exception {
  const PriceFetchException(this.message);

  final String message;

  @override
  String toString() => '行情拉取失败: $message';
}

/// 一次批量刷新的结果统计（用于 UI 提示）。
class PriceRefreshReport {
  const PriceRefreshReport({
    required this.updated,
    required this.suspended,
    required this.notFound,
    required this.failed,
  });

  static const empty = PriceRefreshReport(
    updated: 0,
    suspended: 0,
    notFound: 0,
    failed: 0,
  );

  /// 成功写入缓存的只数。
  final int updated;

  /// 停牌只数。
  final int suspended;

  /// 代码不存在只数。
  final int notFound;

  /// 拉取失败（网络/解析异常）只数。
  final int failed;

  int get total => updated + suspended + notFound + failed;

  bool get allUpdated => total > 0 && updated == total;

  /// 一句话结果，直接用于 SnackBar。
  String get summary {
    if (total == 0) return '暂无持仓，无需刷新';
    if (allUpdated) return '已更新 $updated 只报价';
    final parts = <String>['更新 $updated 只'];
    if (suspended > 0) parts.add('停牌 $suspended 只');
    if (notFound > 0) parts.add('代码不存在 $notFound 只');
    if (failed > 0) parts.add('拉取失败 $failed 只');
    return '${parts.join('，')}（未更新的沿用缓存价）';
  }
}
