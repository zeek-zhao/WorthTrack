import 'package:drift/drift.dart';

import '../../core/stream_utils.dart';
import '../../domain/position_valuation.dart';
import '../../domain/repositories/position_repository.dart';
import '../dao/position_dao.dart';
import '../db/app_database.dart';

/// [PositionRepository] 的 Drift 实现：
/// 持仓流 × 价格缓存流 → 估值流（Dart 端组合，避免 join 与 intEnum 的坑）。
class PositionRepositoryImpl implements PositionRepository {
  PositionRepositoryImpl(this._dao);

  final PositionDao _dao;

  @override
  Stream<List<PositionValuation>> watchValuations({
    bool includeArchived = false,
  }) {
    return combineLatest2(
      _dao.watchPositions(includeArchived: includeArchived),
      _dao.watchPrices(),
      (positions, prices) => positions.map((p) {
        final cached = prices[positionSymbol(p.market, p.code)];
        return PositionValuation(
          position: p,
          priceMinor: cached?.priceMinor,
          priceUpdatedAt: cached?.updatedAt,
        );
      }).toList(),
    );
  }

  @override
  Future<int> createPosition({
    required Market market,
    required String code,
    required String name,
    required int sharesCent,
    required int costPriceMinor,
  }) async {
    final existing = await _dao.getByMarketCode(market, code);
    if (existing != null) {
      throw PositionExistsException(code);
    }
    return _dao.createPosition(
      PositionsCompanion.insert(
        market: market,
        code: code,
        name: name,
        sharesCent: sharesCent,
        costPriceMinor: costPriceMinor,
      ),
    );
  }

  @override
  Future<void> updatePosition({
    required int id,
    String? name,
    int? sharesCent,
    int? costPriceMinor,
  }) {
    return _dao.updatePosition(
      id,
      PositionsCompanion(
        name: name == null ? const Value.absent() : Value(name),
        sharesCent: sharesCent == null
            ? const Value.absent()
            : Value(sharesCent),
        costPriceMinor: costPriceMinor == null
            ? const Value.absent()
            : Value(costPriceMinor),
      ),
    );
  }

  @override
  Future<void> archivePosition(int id) => _dao.archivePosition(id);

  @override
  Future<void> deletePosition(int id) => _dao.deletePosition(id);

  @override
  Future<void> setPrice({
    required Market market,
    required String code,
    required int priceMinor,
  }) {
    return _dao.upsertPrice(positionSymbol(market, code), priceMinor);
  }
}
