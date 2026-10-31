import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:worthtrack/data/db/app_database.dart';
import 'package:worthtrack/modules/finance/domain/position_valuation.dart';
import 'package:worthtrack/modules/finance/domain/price_provider.dart';
import 'package:worthtrack/modules/finance/domain/repositories/position_repository.dart';

import 'fake_transaction_repository.dart' show valueStream;

/// 内存假持仓仓储：驱动 UI 测试，不依赖数据库。
///
/// 与其它假仓储一致：单一 `_changes` 广播源 + `valueStream` 派生估值流。
class FakePositionRepository implements PositionRepository {
  final _changes = StreamController<void>.broadcast();
  final _positions = <Position>[];
  final _prices = <String, (int, DateTime)>{};
  int _nextId = 1;

  /// 直接推送持仓列表（覆盖式）。
  void emit(List<Position> positions) {
    _positions
      ..clear()
      ..addAll(positions);
    _changes.add(null);
  }

  /// 直接推送价格（模拟行情/手动改价）。
  void emitPrice(Market market, String code, int priceMinor) {
    _prices[positionSymbol(market, code)] = (
      priceMinor,
      DateTime(2026, 10, 27, 15),
    );
    _changes.add(null);
  }

  List<PositionValuation> _compute({bool includeArchived = false}) {
    return [
      for (final p in _positions)
        if (includeArchived || p.archivedAt == null)
          PositionValuation(
            position: p,
            priceMinor: _prices[positionSymbol(p.market, p.code)]?.$1,
            priceUpdatedAt: _prices[positionSymbol(p.market, p.code)]?.$2,
          ),
    ];
  }

  @override
  Stream<List<PositionValuation>> watchValuations({
    bool includeArchived = false,
  }) {
    return valueStream(
      () => _compute(includeArchived: includeArchived),
      _changes.stream,
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
    if (_positions.any((p) => p.market == market && p.code == code)) {
      throw PositionExistsException(code);
    }
    final id = _nextId++;
    _positions.add(
      Position(
        id: id,
        market: market,
        code: code,
        name: name,
        sharesCent: sharesCent,
        costPriceMinor: costPriceMinor,
        archivedAt: null,
        createdAt: DateTime(2026, 10, 27),
      ),
    );
    _changes.add(null);
    return id;
  }

  @override
  Future<void> updatePosition({
    required int id,
    String? name,
    int? sharesCent,
    int? costPriceMinor,
  }) async {
    final index = _positions.indexWhere((p) => p.id == id);
    if (index < 0) return;
    _positions[index] = _positions[index].copyWith(
      name: name,
      sharesCent: sharesCent,
      costPriceMinor: costPriceMinor,
    );
    _changes.add(null);
  }

  @override
  Future<void> archivePosition(int id) async {
    final index = _positions.indexWhere((p) => p.id == id);
    if (index < 0) return;
    _positions[index] = _positions[index].copyWith(
      archivedAt: Value(DateTime(2026, 10, 27)),
    );
    _changes.add(null);
  }

  @override
  Future<void> deletePosition(int id) async {
    _positions.removeWhere((p) => p.id == id);
    _changes.add(null);
  }

  @override
  Future<void> setPrice({
    required Market market,
    required String code,
    required int priceMinor,
  }) async {
    emitPrice(market, code, priceMinor);
  }

  /// 下一次 [refreshPrices] 的返回结果。
  PriceRefreshReport refreshReport = PriceRefreshReport.empty;

  /// 模拟行情刷新会写入的报价（symbol → 分）；写入后推一次变更。
  final Map<String, int> nextQuotes = {};

  /// 被调用次数，供断言。
  int refreshCalls = 0;

  @override
  Future<PriceRefreshReport> refreshPrices() async {
    refreshCalls++;
    if (nextQuotes.isNotEmpty) {
      nextQuotes.forEach((symbol, price) {
        _prices[symbol] = (price, DateTime(2026, 10, 27, 15));
      });
      nextQuotes.clear();
      _changes.add(null);
    }
    return refreshReport;
  }

  void dispose() => _changes.close();
}

/// 构造测试用持仓。
Position makeTestPosition({
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
