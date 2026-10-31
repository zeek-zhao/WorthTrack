import 'dart:convert';
import 'dart:math' show min;

import 'package:fast_gbk/fast_gbk.dart';
import 'package:http/http.dart' as http;

import 'package:worthtrack/domain/price_provider.dart';

/// 腾讯财经行情实现（issue #14）。
///
/// 接口：`https://qt.gtimg.cn/q=sh600519,sz159915`，公开无 key。
/// 返回 GBK 文本，每只一行：
/// `v_sh600519="1~贵州茅台~600519~1355.90~1349.98~1343.88~...";`
///
/// 字段位置（腾讯行情固定布局）：
/// - `[1]` 名称、`[2]` 代码、`[3]` 现价、`[4]` 昨收、`[5]` 今开
/// - `[30]` 行情时间 `yyyyMMddHHmmss`、`[33]` 最高、`[34]` 最低
class TencentPriceProvider implements PriceProvider {
  TencentPriceProvider({
    http.Client? client,
    this.baseUrl = 'https://qt.gtimg.cn/q=',
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;

  /// 单次请求的代码上限，避免 URL 过长被拒。
  static const maxSymbolsPerRequest = 50;

  @override
  Future<Map<String, Quote>> fetchQuotes(List<String> symbols) async {
    if (symbols.isEmpty) return const {};
    final result = <String, Quote>{};
    for (var i = 0; i < symbols.length; i += maxSymbolsPerRequest) {
      final chunk = symbols.sublist(
        i,
        min(i + maxSymbolsPerRequest, symbols.length),
      );
      result.addAll(await _fetchChunk(chunk));
    }
    return result;
  }

  Future<Map<String, Quote>> _fetchChunk(List<String> symbols) async {
    final uri = Uri.parse('$baseUrl${symbols.join(',')}');
    final http.Response response;
    try {
      response = await _client.get(
        uri,
        headers: const {'Referer': 'https://gu.qq.com/'},
      );
    } on Exception catch (error) {
      throw PriceFetchException('$error');
    }
    if (response.statusCode != 200) {
      throw PriceFetchException('HTTP ${response.statusCode}');
    }
    return parseTencentQuotes(
      decodeGbk(response.bodyBytes),
      requested: symbols,
    );
  }
}

/// 腾讯响应是 GBK 编码（名称含中文）。
///
/// **必须按 GBK 解码后再按 `~` 切分**：0x7E（`~`）是合法的 GBK 尾字节，
/// 若用 latin1/utf8 直接解码再切分，名称里的字节会被误当作分隔符导致列错位。
String decodeGbk(List<int> bytes) {
  try {
    return gbk.decode(bytes);
  } on FormatException {
    return utf8.decode(bytes, allowMalformed: true);
  }
}

/// 解析腾讯行情响应体。
///
/// [requested] 为本次请求的代码列表：响应里缺失的代码记为
/// [QuoteStatus.notFound]（腾讯对不存在的代码直接不返回，而不是报错）。
Map<String, Quote> parseTencentQuotes(
  String body, {
  List<String> requested = const [],
}) {
  final quotes = <String, Quote>{};
  for (final segment in body.split(';')) {
    final line = segment.trim();
    if (!line.startsWith('v_')) continue;
    final eq = line.indexOf('=');
    if (eq <= 2) continue;
    final symbol = line.substring(2, eq).trim();
    // 全部代码都无效时腾讯只返回 v_pv_none_match="1"
    if (symbol == 'pv_none_match') continue;
    var payload = line.substring(eq + 1).trim();
    if (payload.startsWith('"')) payload = payload.substring(1);
    if (payload.endsWith('"')) {
      payload = payload.substring(0, payload.length - 1);
    }
    quotes[symbol] = _parseQuote(symbol, payload);
  }
  for (final symbol in requested) {
    quotes.putIfAbsent(
      symbol,
      () => Quote(symbol: symbol, status: QuoteStatus.notFound),
    );
  }
  return quotes;
}

Quote _parseQuote(String symbol, String payload) {
  if (payload.isEmpty) {
    return Quote(symbol: symbol, status: QuoteStatus.notFound);
  }
  final fields = payload.split('~');
  // 至少要有 名称/代码/现价 三列才有意义。
  if (fields.length <= 3) {
    return Quote(symbol: symbol, status: QuoteStatus.notFound);
  }
  final quotedAt = fields.length > 30 ? parseQuoteTime(fields[30]) : null;
  final priceMinor = parsePriceMinor(fields[3]);
  if (priceMinor == null) {
    return Quote(symbol: symbol, status: QuoteStatus.notFound);
  }
  if (priceMinor <= 0) {
    // 停牌/无成交：接口给 0，不覆盖缓存价。
    return Quote(
      symbol: symbol,
      status: QuoteStatus.suspended,
      quotedAt: quotedAt,
    );
  }
  return Quote(
    symbol: symbol,
    status: QuoteStatus.ok,
    priceMinor: priceMinor,
    quotedAt: quotedAt,
  );
}

/// 报价字符串 → 分（四舍五入）。
///
/// 场内基金报价到 0.001 元，而价格字段以「分」存储，因此 3 位小数
/// 会四舍五入到分（每份误差 ≤ 0.5 分）；股票 2 位小数无损。
int? parsePriceMinor(String raw) {
  final text = raw.trim();
  final match = RegExp(r'^(\d+)(?:\.(\d+))?$').firstMatch(text);
  if (match == null) return null;
  final yuan = int.parse(match.group(1)!);
  final fraction = (match.group(2) ?? '').padRight(3, '0');
  final thousandths = int.parse(fraction.substring(0, 3));
  return yuan * 100 + (thousandths + 5) ~/ 10;
}

/// `yyyyMMddHHmmss` → DateTime；格式不符返回 null。
DateTime? parseQuoteTime(String raw) {
  final text = raw.trim();
  if (!RegExp(r'^\d{14}$').hasMatch(text)) return null;
  final year = int.parse(text.substring(0, 4));
  final month = int.parse(text.substring(4, 6));
  final day = int.parse(text.substring(6, 8));
  final hour = int.parse(text.substring(8, 10));
  final minute = int.parse(text.substring(10, 12));
  final second = int.parse(text.substring(12, 14));
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  if (hour > 23 || minute > 59 || second > 59) return null;
  return DateTime(year, month, day, hour, minute, second);
}
