/// 资产总览与净资产（issue #16）。
///
/// ## 口径
///
/// **净资产 = 现金类账户余额 + 持仓市值**
///
/// - 现金类 = 现金 + 储蓄卡 + 信用卡（信用卡余额为负时自动抵减）
/// - **投资账户余额不计入**：持仓市值已经代表这部分资产，两者同时计入会重复
///   计算（v1.0 持仓与账户之间没有买卖流水关联）。UI 会单独提示这笔余额。
/// - 无现价的持仓不计入市值，与持仓页 [PortfolioSummary] 口径保持一致。
///
/// ## 历史曲线
///
/// 没有余额快照表，历史净资产由「当前净资产反向回溯」得到：
///
/// ```
/// 净资产(t) = 当前净资产
///           − t 之后发生的收支净额
///           − t 之后才建立的持仓市值
///           − t 之后才创建的账户余额
/// ```
///
/// 转账不影响净资产（内部搬运），因此不参与回溯。
/// 已知限制：行情无历史，历史各期持仓一律按**当前市值**折算，
/// 曲线只反映仓位增减与收支，不反映浮盈浮亏的时间分布。
library;

import '../core/money.dart';
import '../data/db/app_database.dart';
import 'position_valuation.dart';

/// 计入净资产的账户类型（现金 / 储蓄卡 / 信用卡）。
const Set<AccountType> cashLikeAccountTypes = {
  AccountType.cash,
  AccountType.bank,
  AccountType.credit,
};

/// 现金类账户余额之和（信用卡为负时抵减）。
int cashLikeBalanceMinor(Iterable<Account> accounts) {
  var sum = 0;
  for (final a in accounts) {
    if (cashLikeAccountTypes.contains(a.type)) {
      sum += a.balanceMinor;
    }
  }
  return sum;
}

/// 投资账户余额之和：**不计入净资产**，仅用于 UI 提示。
int investmentAccountBalanceMinor(Iterable<Account> accounts) {
  var sum = 0;
  for (final a in accounts) {
    if (a.type == AccountType.investment) {
      sum += a.balanceMinor;
    }
  }
  return sum;
}

/// 持仓市值之和；无现价的持仓按 0 计。
int investmentValueMinor(Iterable<PositionValuation> valuations) {
  var sum = 0;
  for (final v in valuations) {
    sum += v.marketValueMinor ?? 0;
  }
  return sum;
}

/// 未录现价的持仓只数（市值被低估的提示依据）。
int unpricedPositionCount(Iterable<PositionValuation> valuations) {
  var count = 0;
  for (final v in valuations) {
    if (!v.hasPrice) {
      count++;
    }
  }
  return count;
}

/// 单笔交易对净资产的影响：支出为负、收入为正、转账为 0。
int netWorthDeltaMinor(TxnType type, int amountMinor) => switch (type) {
  TxnType.expense => -amountMinor,
  TxnType.income => amountMinor,
  TxnType.transfer => 0,
};

/// 净资产回溯用的交易投影（只保留时间/类型/金额）。
class NetWorthTxn {
  const NetWorthTxn({
    required this.occurredAt,
    required this.type,
    required this.amountMinor,
  });

  final DateTime occurredAt;
  final TxnType type;
  final int amountMinor;
}

/// 净资产回溯用的持仓投影。
class NetWorthPosition {
  const NetWorthPosition({
    required this.createdAt,
    required this.marketValueMinor,
  });

  final DateTime createdAt;

  /// 当前市值（无现价时为 0）。
  final int marketValueMinor;
}

/// 净资产回溯用的现金类账户投影。
class NetWorthAccount {
  const NetWorthAccount({required this.createdAt, required this.balanceMinor});

  final DateTime createdAt;

  /// 当前余额。
  final int balanceMinor;
}

/// 曲线上的一个点。
class NetWorthPoint {
  const NetWorthPoint({required this.month, required this.netWorthMinor});

  /// 归属月份（当月 1 日 00:00）。
  final DateTime month;

  /// 该月**月末**的净资产。
  final int netWorthMinor;

  @override
  String toString() =>
      'NetWorthPoint(${month.year}-${month.month}, $netWorthMinor)';
}

/// 资产总览：拆分 + 历史序列（资产页一次订阅拿全）。
class AssetOverview {
  const AssetOverview({
    required this.cashMinor,
    required this.investmentMinor,
    required this.investmentAccountBalanceMinor,
    required this.unpricedPositionCount,
    required this.series,
  });

  /// 现金类余额（现金 + 储蓄卡 + 信用卡）。
  final int cashMinor;

  /// 持仓市值（只计有现价的）。
  final int investmentMinor;

  /// 投资账户余额（提示用，不计入净资产）。
  final int investmentAccountBalanceMinor;

  /// 未录价持仓只数。
  final int unpricedPositionCount;

  /// 近 N 个月净资产，按时间升序；数据不足时可能为空或只有 1 个点。
  final List<NetWorthPoint> series;

  /// 净资产 = 现金类 + 投资市值。
  int get netWorthMinor => cashMinor + investmentMinor;

  /// 完全没有数据（空账本）——UI 显示引导而非 0.00 曲线。
  bool get isEmpty =>
      cashMinor == 0 &&
      investmentMinor == 0 &&
      investmentAccountBalanceMinor == 0 &&
      series.isEmpty;

  static const empty = AssetOverview(
    cashMinor: 0,
    investmentMinor: 0,
    investmentAccountBalanceMinor: 0,
    unpricedPositionCount: 0,
    series: [],
  );
}

/// 构造近 [months] 个月的净资产序列（升序，末位为当前月）。
///
/// - 每个点取该月**月末**的值；当前月的值即 [currentNetWorthMinor]。
/// - 首段无任何账目的月份会被裁掉，避免曲线从 0 拉一条长平线。
/// - 完全没有账目时返回空列表。
List<NetWorthPoint> buildMonthlyNetWorthSeries({
  required int currentNetWorthMinor,
  required Iterable<NetWorthTxn> transactions,
  required Iterable<NetWorthPosition> positions,
  required Iterable<NetWorthAccount> accounts,
  required DateTime anchor,
  int months = 12,
}) {
  final txnList = transactions.toList(growable: false);
  final posList = positions.toList(growable: false);
  final accList = accounts.toList(growable: false);
  if (txnList.isEmpty && posList.isEmpty && accList.isEmpty) {
    return const [];
  }

  final first = DateTime(anchor.year, anchor.month - (months - 1));
  final points = <NetWorthPoint>[];
  for (var i = 0; i < months; i++) {
    final month = DateTime(first.year, first.month + i);
    // 月末最后一毫秒：occurredAt 落在该毫秒内的交易算作已发生。
    final cutoff = DateTime(
      month.year,
      month.month + 1,
    ).subtract(const Duration(milliseconds: 1));

    var value = currentNetWorthMinor;
    for (final t in txnList) {
      if (t.occurredAt.isAfter(cutoff)) {
        value -= netWorthDeltaMinor(t.type, t.amountMinor);
      }
    }
    for (final p in posList) {
      if (p.createdAt.isAfter(cutoff)) {
        value -= p.marketValueMinor;
      }
    }
    for (final a in accList) {
      if (a.createdAt.isAfter(cutoff)) {
        value -= a.balanceMinor;
      }
    }
    points.add(NetWorthPoint(month: month, netWorthMinor: value));
  }

  // 裁掉首个有账目月份之前的空档：起点取「窗口起点」与「最早账目月」的较晚者。
  var activityStart = points.first.month;
  var hasActivity = false;
  void consider(DateTime at) {
    final m = DateTime(at.year, at.month);
    if (!hasActivity || m.isBefore(activityStart)) {
      activityStart = m;
      hasActivity = true;
    }
  }

  for (final t in txnList) {
    consider(t.occurredAt);
  }
  for (final p in posList) {
    consider(p.createdAt);
  }
  for (final a in accList) {
    consider(a.createdAt);
  }
  final start = activityStart.isAfter(points.first.month)
      ? activityStart
      : points.first.month;
  return points.where((p) => !p.month.isBefore(start)).toList(growable: false);
}

/// 分 → 紧凑元文本（图表纵轴/摘要用）：`1.2万` / `3.4亿` / `5600`。
String formatCompactYuan(int minor) {
  final yuan = minor / 100;
  final abs = yuan.abs();
  final sign = yuan < 0 ? '-' : '';
  if (abs >= 100000000) {
    return '$sign${(abs / 100000000).toStringAsFixed(1)}亿';
  }
  if (abs >= 10000) {
    return '$sign${(abs / 10000).toStringAsFixed(1)}万';
  }
  return '$sign${abs.round()}';
}

/// 曲线相邻两点变化文案：`较上月 +¥1200.00（+2.31%）`。
///
/// 序列不足 2 点时返回 null；上月为 0 时省略百分比。
String? formatSeriesChange(List<NetWorthPoint> series) {
  if (series.length < 2) return null;
  final last = series.last.netWorthMinor;
  final prev = series[series.length - 2].netWorthMinor;
  final delta = last - prev;
  final sign = delta > 0 ? '+' : '';
  final pct = prev == 0
      ? ''
      : '（$sign${(delta / prev.abs() * 100).toStringAsFixed(2)}%）';
  return '较上月 $sign${Money.toYuanSymbol(delta)}$pct';
}
