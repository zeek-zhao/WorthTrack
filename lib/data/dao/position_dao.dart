import 'package:drift/drift.dart';

import '../db/app_database.dart';

part 'position_dao.g.dart';

/// 持仓与行情缓存 DAO（issue #13）。
@DriftAccessor(tables: [Positions, PriceCache])
class PositionDao extends DatabaseAccessor<AppDatabase>
    with _$PositionDaoMixin {
  PositionDao(super.db);

  /// 监听持仓（默认不含归档），按市场、代码排序保证展示稳定。
  Stream<List<Position>> watchPositions({bool includeArchived = false}) {
    final query = select(positions);
    if (!includeArchived) {
      query.where((p) => p.archivedAt.isNull());
    }
    query.orderBy([
      (p) => OrderingTerm.asc(p.market),
      (p) => OrderingTerm.asc(p.code),
    ]);
    return query.watch();
  }

  Future<Position?> getById(int id) {
    return (select(positions)..where((p) => p.id.equals(id))).getSingleOrNull();
  }

  /// 按「市场 + 代码」查重（唯一键 market+code）。
  Future<Position?> getByMarketCode(Market market, String code) {
    return (select(positions)
          ..where((p) => p.market.equalsValue(market) & p.code.equals(code)))
        .getSingleOrNull();
  }

  Future<int> createPosition(PositionsCompanion entry) {
    return into(positions).insert(entry);
  }

  Future<void> updatePosition(int id, PositionsCompanion entry) {
    return (update(positions)..where((p) => p.id.equals(id))).write(entry);
  }

  /// 归档（清仓软删除）：不再计入持仓与市值。
  Future<void> archivePosition(int id) {
    return (update(positions)..where((p) => p.id.equals(id))).write(
      PositionsCompanion(archivedAt: Value(DateTime.now())),
    );
  }

  /// 物理删除（录错时用）。
  Future<void> deletePosition(int id) {
    return (delete(positions)..where((p) => p.id.equals(id))).go();
  }

  /// 监听全部价格缓存，key 为行情代码（如 sh600519）。
  ///
  /// 表很小（一只持仓一行），整表读出在 Dart 端建索引即可。
  /// 注意：PriceCache 使用自定义主键，drift 生成的行类名是 [PriceCacheData]。
  Stream<Map<String, PriceCacheData>> watchPrices() {
    return select(
      priceCache,
    ).watch().map((rows) => {for (final row in rows) row.symbol: row});
  }

  Future<PriceCacheData?> getPrice(String symbol) {
    return (select(
      priceCache,
    )..where((p) => p.symbol.equals(symbol))).getSingleOrNull();
  }

  /// 写入/覆盖现价（主键 symbol，幂等 upsert）。
  Future<void> upsertPrice(String symbol, int priceMinor) async {
    await into(priceCache).insertOnConflictUpdate(
      PriceCacheCompanion.insert(
        symbol: symbol,
        priceMinor: priceMinor,
        updatedAt: DateTime.now(),
      ),
    );
  }
}
