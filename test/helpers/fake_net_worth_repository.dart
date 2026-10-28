import 'dart:async';

import 'package:worthtrack/domain/net_worth.dart';
import 'package:worthtrack/domain/repositories/net_worth_repository.dart';

import 'fake_transaction_repository.dart' show replayStream;

/// 内存假实现：驱动资产页 Widget 测试，不依赖数据库。
///
/// 与账户假仓储**不做自动联动**——测试里显式 `emit` 总览，
/// 避免两条流的事件顺序影响断言（订阅时回放当前值）。
class FakeNetWorthRepository implements NetWorthRepository {
  final _controller = StreamController<AssetOverview>.broadcast();
  AssetOverview _current = AssetOverview.empty;

  /// 当前值（测试断言用）。
  AssetOverview get current => _current;

  void emit(AssetOverview overview) {
    _current = overview;
    _controller.add(overview);
  }

  @override
  Stream<AssetOverview> watchOverview({int months = 12}) =>
      replayStream(_current, _controller);

  void dispose() => _controller.close();
}

/// 构造测试用总览。
AssetOverview makeTestOverview({
  int cashMinor = 0,
  int investmentMinor = 0,
  int investmentAccountBalanceMinor = 0,
  int unpricedPositionCount = 0,
  List<NetWorthPoint>? series,
}) => AssetOverview(
  cashMinor: cashMinor,
  investmentMinor: investmentMinor,
  investmentAccountBalanceMinor: investmentAccountBalanceMinor,
  unpricedPositionCount: unpricedPositionCount,
  series: series ?? const [],
);

/// 构造测试用净资产序列：[values] 依次落在 [endMonth] 及之前各月。
List<NetWorthPoint> makeTestSeries(List<int> values, {DateTime? endMonth}) {
  final end = endMonth ?? DateTime(2026, 10);
  return [
    for (var i = 0; i < values.length; i++)
      NetWorthPoint(
        month: DateTime(end.year, end.month - (values.length - 1 - i)),
        netWorthMinor: values[i],
      ),
  ];
}
