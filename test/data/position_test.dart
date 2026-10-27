import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worthtrack/data/db/app_database.dart';
import 'package:worthtrack/data/repositories/position_repository_impl.dart';
import 'package:worthtrack/domain/price_provider.dart';
import 'package:worthtrack/domain/repositories/position_repository.dart';

import '../helpers/sqlite3_loader.dart';

/// 本文件不测行情，行情源用空实现占位。
class _NoopPriceProvider implements PriceProvider {
  @override
  Future<Map<String, Quote>> fetchQuotes(List<String> symbols) async =>
      const {};
}

/// issue #13 验收：持仓 CRUD + 价格缓存 → 估值流（真 Drift 内存库）。
void main() {
  setUpAll(setupSqlite3ForTests);

  late AppDatabase db;
  late PositionRepositoryImpl repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = PositionRepositoryImpl(db.positionDao, _NoopPriceProvider());
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> addMoutai({int sharesCent = 15000, int cost = 160000}) {
    return repo.createPosition(
      market: Market.sh,
      code: '600519',
      name: '贵州茅台',
      sharesCent: sharesCent,
      costPriceMinor: cost,
    );
  }

  group('持仓 CRUD', () {
    test('新建后出现在估值流；未录价时市值/盈亏为 null，成本仍可算', () async {
      await addMoutai();

      final list = await repo.watchValuations().first;
      expect(list, hasLength(1));
      final v = list.single;
      expect(v.position.name, '贵州茅台');
      expect(v.symbol, 'sh600519');
      expect(v.hasPrice, isFalse);
      expect(v.costMinor, 24000000);
      expect(v.marketValueMinor, isNull);
      expect(v.profitMinor, isNull);
    });

    test('同市场同代码重复建仓抛 PositionExistsException', () async {
      await addMoutai();

      await expectLater(addMoutai(), throwsA(isA<PositionExistsException>()));
    });

    test('唯一键含 market：沪深同代码可共存', () async {
      await addMoutai();
      await repo.createPosition(
        market: Market.sz,
        code: '600519',
        name: '同名不同市',
        sharesCent: 100,
        costPriceMinor: 100,
      );

      expect(await repo.watchValuations().first, hasLength(2));
    });

    test('updatePosition 局部更新：只改传入字段', () async {
      final id = await addMoutai();

      await repo.updatePosition(id: id, sharesCent: 20000);

      final v = (await repo.watchValuations().first).single;
      expect(v.position.sharesCent, 20000);
      expect(v.position.costPriceMinor, 160000);
      expect(v.position.name, '贵州茅台');
    });

    test('归档后不计入估值流，includeArchived 仍可查', () async {
      final id = await addMoutai();

      await repo.archivePosition(id);

      expect(await repo.watchValuations().first, isEmpty);
      final all = await repo.watchValuations(includeArchived: true).first;
      expect(all, hasLength(1));
      expect(all.single.position.archivedAt, isNotNull);
    });

    test('删除后从估值流消失', () async {
      final id = await addMoutai();

      await repo.deletePosition(id);

      expect(await repo.watchValuations().first, isEmpty);
    });

    test('按市场、代码排序', () async {
      await repo.createPosition(
        market: Market.sz,
        code: '159915',
        name: '创业板ETF',
        sharesCent: 100,
        costPriceMinor: 100,
      );
      await addMoutai();

      final symbols = (await repo.watchValuations().first)
          .map((v) => v.symbol)
          .toList();
      expect(symbols, ['sh600519', 'sz159915']);
    });
  });

  group('价格缓存与估值联动', () {
    test('setPrice 后市值/盈亏/百分比即时更新，并记录更新时间', () async {
      await addMoutai();

      await repo.setPrice(
        market: Market.sh,
        code: '600519',
        priceMinor: 170000,
      );

      final v = (await repo.watchValuations().first).single;
      expect(v.priceMinor, 170000);
      expect(v.priceUpdatedAt, isNotNull);
      expect(v.marketValueMinor, 25500000);
      expect(v.profitMinor, 1500000);
      expect(v.profitPercent, closeTo(6.25, 1e-9));
    });

    test('重复 setPrice 覆盖同一行（主键 symbol，幂等）', () async {
      await addMoutai();
      await repo.setPrice(
        market: Market.sh,
        code: '600519',
        priceMinor: 170000,
      );

      await repo.setPrice(
        market: Market.sh,
        code: '600519',
        priceMinor: 150000,
      );

      final prices = await db.positionDao.watchPrices().first;
      expect(prices, hasLength(1));
      final v = (await repo.watchValuations().first).single;
      expect(v.marketValueMinor, 22500000);
      expect(v.profitMinor, -1500000);
    });

    test('价格按 symbol 存储，未缓存代码查不到', () async {
      await addMoutai();
      await repo.setPrice(
        market: Market.sh,
        code: '600519',
        priceMinor: 170000,
      );

      final cached = await db.positionDao.getPrice('sh600519');
      expect(cached!.priceMinor, 170000);
      expect(await db.positionDao.getPrice('sz000001'), isNull);
    });

    test('改份额后市值随份额变化（价格不变）', () async {
      final id = await addMoutai();
      await repo.setPrice(
        market: Market.sh,
        code: '600519',
        priceMinor: 170000,
      );

      await repo.updatePosition(id: id, sharesCent: 30000);

      final v = (await repo.watchValuations().first).single;
      expect(v.marketValueMinor, 51000000);
      expect(v.costMinor, 48000000);
    });
  });
}
