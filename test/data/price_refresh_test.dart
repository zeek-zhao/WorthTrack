import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worthtrack/data/db/app_database.dart';
import 'package:worthtrack/data/repositories/position_repository_impl.dart';
import 'package:worthtrack/domain/price_provider.dart';

import '../helpers/sqlite3_loader.dart';

/// 桩行情源：按预设报价返回，可模拟整批失败。
class _StubPriceProvider implements PriceProvider {
  _StubPriceProvider(this.quotes);

  final Map<String, Quote> quotes;
  bool shouldThrow = false;

  /// 最近一次被请求的代码（供断言）。
  List<String>? requested;

  @override
  Future<Map<String, Quote>> fetchQuotes(List<String> symbols) async {
    requested = symbols;
    if (shouldThrow) throw const PriceFetchException('模拟断网');
    return {
      for (final symbol in symbols)
        if (quotes.containsKey(symbol)) symbol: quotes[symbol]!,
    };
  }
}

/// issue #14 验收：批量刷新行情 → 落 price_cache → 估值流市值更新。
void main() {
  setUpAll(setupSqlite3ForTests);

  late AppDatabase db;
  late _StubPriceProvider provider;
  late PositionRepositoryImpl repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    provider = _StubPriceProvider({});
    repo = PositionRepositoryImpl(db.positionDao, provider);
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> addMoutai() => repo.createPosition(
    market: Market.sh,
    code: '600519',
    name: '贵州茅台',
    sharesCent: 15000,
    costPriceMinor: 160000,
  );

  group('刷新成功', () {
    test('写入缓存价后估值流市值/盈亏即时更新', () async {
      await addMoutai();
      provider.quotes['sh600519'] = Quote(
        symbol: 'sh600519',
        status: QuoteStatus.ok,
        priceMinor: 170000,
        quotedAt: DateTime(2026, 10, 27, 15),
      );

      final report = await repo.refreshPrices();

      expect(report.updated, 1);
      expect(report.failed, 0);
      expect(provider.requested, ['sh600519']);

      final v = (await repo.watchValuations().first).single;
      expect(v.priceMinor, 170000);
      expect(v.marketValueMinor, 25500000);
      expect(v.profitMinor, 1500000);
      // 缓存时间取行情时间，而不是本地刷新时刻。
      expect(v.priceUpdatedAt, DateTime(2026, 10, 27, 15));
    });

    test('行情时间缺失时回退为本地写入时刻', () async {
      await addMoutai();
      provider.quotes['sh600519'] = const Quote(
        symbol: 'sh600519',
        status: QuoteStatus.ok,
        priceMinor: 170000,
      );

      await repo.refreshPrices();

      final v = (await repo.watchValuations().first).single;
      expect(v.priceUpdatedAt, isNotNull);
    });

    test('多只持仓一次刷新', () async {
      await addMoutai();
      await repo.createPosition(
        market: Market.sz,
        code: '159915',
        name: '创业板ETF',
        sharesCent: 100000,
        costPriceMinor: 1234,
      );
      provider.quotes
        ..['sh600519'] = const Quote(
          symbol: 'sh600519',
          status: QuoteStatus.ok,
          priceMinor: 170000,
        )
        ..['sz159915'] = const Quote(
          symbol: 'sz159915',
          status: QuoteStatus.ok,
          priceMinor: 256,
        );

      final report = await repo.refreshPrices();

      expect(report.updated, 2);
      expect(report.allUpdated, isTrue);
      final list = await repo.watchValuations().first;
      expect(list.map((v) => v.marketValueMinor).toList(), [25500000, 256000]);
    });
  });

  group('兜底：不覆盖缓存价', () {
    test('停牌不覆盖已有缓存价，计入 suspended', () async {
      await addMoutai();
      await repo.setPrice(
        market: Market.sh,
        code: '600519',
        priceMinor: 165000,
      );
      provider.quotes['sh600519'] = const Quote(
        symbol: 'sh600519',
        status: QuoteStatus.suspended,
      );

      final report = await repo.refreshPrices();

      expect(report.suspended, 1);
      expect(report.updated, 0);
      final v = (await repo.watchValuations().first).single;
      expect(v.priceMinor, 165000); // 沿用缓存价
    });

    test('代码不存在不覆盖缓存价，计入 notFound', () async {
      await addMoutai();
      await repo.setPrice(
        market: Market.sh,
        code: '600519',
        priceMinor: 165000,
      );
      // 契约：provider 负责把「响应里缺失的代码」标成 notFound。
      provider.quotes['sh600519'] = const Quote(
        symbol: 'sh600519',
        status: QuoteStatus.notFound,
      );

      final report = await repo.refreshPrices();

      expect(report.notFound, 1);
      expect(report.updated, 0);
      final v = (await repo.watchValuations().first).single;
      expect(v.priceMinor, 165000);
    });

    test('行情源少返回代码时按 failed 兜底（防御性）', () async {
      await addMoutai();
      await repo.setPrice(
        market: Market.sh,
        code: '600519',
        priceMinor: 165000,
      );
      provider.quotes.clear();

      final report = await repo.refreshPrices();

      expect(report.failed, 1);
      final v = (await repo.watchValuations().first).single;
      expect(v.priceMinor, 165000);
    });

    test('整批拉取失败：failed = 持仓数，缓存一条不动', () async {
      await addMoutai();
      await repo.setPrice(
        market: Market.sh,
        code: '600519',
        priceMinor: 165000,
      );
      provider.shouldThrow = true;

      final report = await repo.refreshPrices();

      expect(report.failed, 1);
      expect(report.updated, 0);
      final v = (await repo.watchValuations().first).single;
      expect(v.priceMinor, 165000);
    });
  });

  group('边界', () {
    test('无持仓不发请求', () async {
      final report = await repo.refreshPrices();

      expect(report.total, 0);
      expect(report.summary, '暂无持仓，无需刷新');
      expect(provider.requested, isNull);
    });

    test('已归档持仓不参与刷新', () async {
      final id = await addMoutai();
      await repo.archivePosition(id);

      final report = await repo.refreshPrices();

      expect(report.total, 0);
      expect(provider.requested, isNull);
    });
  });

  group('结果文案', () {
    test('全部成功', () {
      const report = PriceRefreshReport(
        updated: 3,
        suspended: 0,
        notFound: 0,
        failed: 0,
      );
      expect(report.summary, '已更新 3 只报价');
    });

    test('部分失败逐项列出', () {
      const report = PriceRefreshReport(
        updated: 2,
        suspended: 1,
        notFound: 1,
        failed: 1,
      );
      expect(report.summary, '更新 2 只，停牌 1 只，代码不存在 1 只，拉取失败 1 只（未更新的沿用缓存价）');
    });
  });
}
