import 'package:drift/drift.dart';

import '../../core/stream_utils.dart';
import '../../domain/position_valuation.dart';
import '../../domain/price_provider.dart';
import '../../domain/repositories/position_repository.dart';
import '../dao/position_dao.dart';
import '../db/app_database.dart';

/// [PositionRepository] 的 Drift 实现：
/// 持仓流 × 价格缓存流 → 估值流（Dart 端组合，避免 join 与 intEnum 的坑）。
class PositionRepositoryImpl implements PositionRepository {
  PositionRepositoryImpl(this._dao, this._priceProvider);

  final PositionDao _dao;
  final PriceProvider _priceProvider;

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

  @override
  Future<PriceRefreshReport> refreshPrices() async {
    final positions = await _dao.getActivePositions();
    if (positions.isEmpty) return PriceRefreshReport.empty;
    final symbols = [
      for (final p in positions) positionSymbol(p.market, p.code),
    ];

    final Map<String, Quote> quotes;
    try {
      quotes = await _priceProvider.fetchQuotes(symbols);
    } on Exception {
      // 整批失败：一条缓存都不动，交给 #15 的缓存价兜底。
      return PriceRefreshReport(
        updated: 0,
        suspended: 0,
        notFound: 0,
        failed: symbols.length,
      );
    }

    var updated = 0;
    var suspended = 0;
    var notFound = 0;
    var failed = 0;
    for (final symbol in symbols) {
      final quote = quotes[symbol];
      if (quote == null) {
        failed++;
        continue;
      }
      switch (quote.status) {
        case QuoteStatus.ok:
          await _dao.upsertPrice(symbol, quote.priceMinor!, at: quote.quotedAt);
          updated++;
        case QuoteStatus.suspended:
          suspended++;
        case QuoteStatus.notFound:
          notFound++;
      }
    }
    return PriceRefreshReport(
      updated: updated,
      suspended: suspended,
      notFound: notFound,
      failed: failed,
    );
  }
}
