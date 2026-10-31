import 'package:fast_gbk/fast_gbk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:worthtrack/modules/finance/data/price/tencent_price_provider.dart';
import 'package:worthtrack/modules/finance/domain/price_provider.dart';

/// issue #14 验收：腾讯行情响应解析 fixture 单测（正常 / 停牌 / 代码不存在）。
void main() {
  /// 构造一条腾讯行情响应，字段位置与真实响应一致：
  /// `v_sh600519="1~名称~代码~现价~昨收~今开~成交量~...~时间~涨跌~涨跌%~最高~最低";`
  String line(
    String symbol,
    String name,
    String price, {
    String prevClose = '10.00',
    String time = '20261027150000',
  }) {
    final fields = <String>[
      symbol.startsWith('sh') ? '1' : '51',
      name,
      symbol.substring(2),
      price,
      prevClose,
      prevClose,
      '1000',
    ];
    while (fields.length < 30) {
      fields.add('');
    }
    fields
      ..add(time) // [30] 行情时间
      ..add('0.10') // [31] 涨跌
      ..add('1.00') // [32] 涨跌%
      ..add(price) // [33] 最高
      ..add(price); // [34] 最低
    return 'v_$symbol="${fields.join('~')}";';
  }

  group('正常报价', () {
    test('A 股：现价按「分」解析，行情时间解析正确', () {
      final quotes = parseTencentQuotes(
        line('sh600519', '贵州茅台', '1355.90'),
        requested: ['sh600519'],
      );

      final quote = quotes['sh600519']!;
      expect(quote.status, QuoteStatus.ok);
      expect(quote.priceMinor, 135590);
      expect(quote.quotedAt, DateTime(2026, 10, 27, 15));
    });

    test('场内基金：3 位小数四舍五入到分', () {
      final up = parseTencentQuotes(
        line('sz159915', '创业板ETF', '2.563'),
        requested: ['sz159915'],
      );
      final roundUp = parseTencentQuotes(
        line('sz159915', '创业板ETF', '2.567'),
        requested: ['sz159915'],
      );

      expect(up['sz159915']!.priceMinor, 256); // 2.563 → 256.3 分
      expect(roundUp['sz159915']!.priceMinor, 257); // 2.567 → 256.7 分
    });

    test('多只混合响应：逐只独立解析', () {
      final body =
          '${line('sh600519', '贵州茅台', '1355.90')}'
          '${line('sz159915', '创业板ETF', '2.563')}';

      final quotes = parseTencentQuotes(
        body,
        requested: ['sh600519', 'sz159915'],
      );

      expect(quotes, hasLength(2));
      expect(quotes['sh600519']!.priceMinor, 135590);
      expect(quotes['sz159915']!.priceMinor, 256);
    });

    test('GBK 中文名解码后不破坏列切分（按 GBK 解码再按 ~ 切分）', () {
      // 真实响应是 GBK 字节；名称里的中文字节若按 latin1/utf8 硬切，
      // 可能撞上分隔符导致列错位，这里做一次端到端回环验证。
      final body = line('sh600519', '贵州茅台', '1355.90');
      final decoded = decodeGbk(gbk.encode(body));

      expect(decoded, contains('贵州茅台'));
      final quotes = parseTencentQuotes(decoded, requested: ['sh600519']);
      expect(quotes['sh600519']!.priceMinor, 135590);
    });
  });

  group('停牌与异常', () {
    test('停牌（现价 0.00）→ suspended，且不带价格', () {
      final quotes = parseTencentQuotes(
        line('sh600519', '贵州茅台', '0.00'),
        requested: ['sh600519'],
      );

      final quote = quotes['sh600519']!;
      expect(quote.status, QuoteStatus.suspended);
      expect(quote.priceMinor, isNull);
      // 停牌时仍可拿到行情时间（用于 UI 标注）。
      expect(quote.quotedAt, isNotNull);
    });

    test('代码不存在：响应里缺失 → notFound', () {
      final quotes = parseTencentQuotes(
        line('sh600519', '贵州茅台', '1355.90'),
        requested: ['sh600519', 'sh999999'],
      );

      expect(quotes['sh999999']!.status, QuoteStatus.notFound);
      expect(quotes['sh999999']!.priceMinor, isNull);
    });

    test('v_pv_none_match 不产生伪代码，全部记为 notFound', () {
      final quotes = parseTencentQuotes(
        'v_pv_none_match="1";',
        requested: ['sh999999', 'sz888888'],
      );

      expect(quotes.containsKey('pv_none_match'), isFalse);
      expect(quotes['sh999999']!.status, QuoteStatus.notFound);
      expect(quotes['sz888888']!.status, QuoteStatus.notFound);
    });

    test('空 payload（v_sh600519=""）→ notFound', () {
      final quotes = parseTencentQuotes(
        'v_sh600519="";',
        requested: ['sh600519'],
      );

      expect(quotes['sh600519']!.status, QuoteStatus.notFound);
    });

    test('字段不足/格式异常不抛异常，降级为 notFound', () {
      final quotes = parseTencentQuotes(
        'v_sh600519="1~贵州茅台";v_sz000001="1~平安银行~000001~abc~10~10";',
        requested: ['sh600519', 'sz000001'],
      );

      expect(quotes['sh600519']!.status, QuoteStatus.notFound);
      expect(quotes['sz000001']!.status, QuoteStatus.notFound);
    });

    test('空响应体 → 请求的代码全为 notFound', () {
      final quotes = parseTencentQuotes('', requested: ['sh600519']);

      expect(quotes['sh600519']!.status, QuoteStatus.notFound);
    });
  });

  group('数值解析边界', () {
    test('parsePriceMinor', () {
      expect(parsePriceMinor('0'), 0);
      expect(parsePriceMinor('0.00'), 0);
      expect(parsePriceMinor('1'), 100);
      expect(parsePriceMinor('1.2'), 120);
      expect(parsePriceMinor('1.23'), 123);
      expect(parsePriceMinor('1.234'), 123);
      expect(parsePriceMinor('1.235'), 124);
      expect(parsePriceMinor('1355.90'), 135590);
      expect(parsePriceMinor('abc'), isNull);
      expect(parsePriceMinor('-1.00'), isNull);
      expect(parsePriceMinor('1.2.3'), isNull);
      expect(parsePriceMinor(''), isNull);
    });

    test('parseQuoteTime', () {
      expect(
        parseQuoteTime('20261027161452'),
        DateTime(2026, 10, 27, 16, 14, 52),
      );
      expect(parseQuoteTime('20261327161452'), isNull); // 13 月
      expect(parseQuoteTime('2026102716'), isNull); // 长度不足
      expect(parseQuoteTime(''), isNull);
      expect(parseQuoteTime('abcdefghijklmn'), isNull);
    });
  });

  group('网络层（mock HTTP）', () {
    test('请求 URL 与 Referer 正确，GBK 响应被正确解码', () async {
      final body = line('sh600519', '贵州茅台', '1355.90');
      final client = MockClient((request) async {
        expect(request.url.toString(), 'https://qt.gtimg.cn/q=sh600519');
        expect(request.headers['Referer'], 'https://gu.qq.com/');
        return http.Response.bytes(gbk.encode(body), 200);
      });

      final quotes = await TencentPriceProvider(
        client: client,
      ).fetchQuotes(['sh600519']);

      expect(quotes['sh600519']!.priceMinor, 135590);
    });

    test('HTTP 500 → PriceFetchException', () async {
      final client = MockClient((_) async => http.Response('oops', 500));

      await expectLater(
        TencentPriceProvider(client: client).fetchQuotes(['sh600519']),
        throwsA(isA<PriceFetchException>()),
      );
    });

    test('网络异常 → PriceFetchException', () async {
      final client = MockClient((_) async => throw http.ClientException('断网'));

      await expectLater(
        TencentPriceProvider(client: client).fetchQuotes(['sh600519']),
        throwsA(isA<PriceFetchException>()),
      );
    });

    test('空代码列表不发请求', () async {
      var called = 0;
      final client = MockClient((_) async {
        called++;
        return http.Response('', 200);
      });

      expect(
        await TencentPriceProvider(client: client).fetchQuotes([]),
        isEmpty,
      );
      expect(called, 0);
    });

    test('超过单次上限时拆成多次请求', () async {
      final urls = <String>[];
      final client = MockClient((request) async {
        urls.add(request.url.toString());
        return http.Response.bytes(const [], 200);
      });
      final symbols = [
        for (var i = 0; i < TencentPriceProvider.maxSymbolsPerRequest + 1; i++)
          'sh${(600000 + i)}',
      ];

      await TencentPriceProvider(client: client).fetchQuotes(symbols);

      expect(urls, hasLength(2));
      expect(
        urls.first.split('q=').last.split(','),
        hasLength(TencentPriceProvider.maxSymbolsPerRequest),
      );
    });
  });
}
