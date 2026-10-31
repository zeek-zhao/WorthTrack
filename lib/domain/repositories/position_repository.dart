import 'package:worthtrack/data/db/app_database.dart';
import 'package:worthtrack/domain/position_valuation.dart';
import 'package:worthtrack/domain/price_provider.dart';

/// 持仓领域接口（issue #13）。
///
/// 持仓不绑定具体账户（v1.0 决策）：同一市场同一代码全局唯一一条，
/// 跨券商持有的同一只股票自然合并。
abstract class PositionRepository {
  /// 监听持仓估值列表（默认不含归档）。
  Stream<List<PositionValuation>> watchValuations({
    bool includeArchived = false,
  });

  /// 新建持仓；同市场同代码已存在时抛 [PositionExistsException]。
  Future<int> createPosition({
    required Market market,
    required String code,
    required String name,
    required int sharesCent,
    required int costPriceMinor,
  });

  /// 修改持仓。市场与代码不可变（换股票请删了重建），其余字段可局部更新。
  Future<void> updatePosition({
    required int id,
    String? name,
    int? sharesCent,
    int? costPriceMinor,
  });

  /// 归档（清仓）：不再计入持仓与市值，价格缓存保留。
  Future<void> archivePosition(int id);

  /// 物理删除（录错时用）。
  Future<void> deletePosition(int id);

  /// 手动录入/覆盖现价（写 price_cache）。M3-#14 起由行情刷新覆盖。
  Future<void> setPrice({
    required Market market,
    required String code,
    required int priceMinor,
  });

  /// 批量刷新行情并落 price_cache（M3-#14）。
  ///
  /// 只写入有有效报价的持仓：停牌 / 代码不存在 / 拉取失败一律**不覆盖**
  /// 已有缓存价（兜底语义见 M3-#15），返回各状态计数供 UI 提示。
  Future<PriceRefreshReport> refreshPrices();
}

/// 同市场同代码重复建仓。
class PositionExistsException implements Exception {
  const PositionExistsException(this.code);

  final String code;

  @override
  String toString() => '持仓已存在: $code';
}
