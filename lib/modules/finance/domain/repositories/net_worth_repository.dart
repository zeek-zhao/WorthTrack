import 'package:worthtrack/modules/finance/domain/net_worth.dart';

/// 资产总览领域接口（issue #16）。
///
/// UI 只依赖此抽象，不直接组合账户 / 持仓 / 交易三条流。
abstract class NetWorthRepository {
  /// 监听资产总览：现金类与投资市值拆分 + 近 [months] 个月净资产序列。
  ///
  /// [months] 上限按窗口裁剪；账目不足时序列会变短（可能为空）。
  Stream<AssetOverview> watchOverview({int months = 12});
}
