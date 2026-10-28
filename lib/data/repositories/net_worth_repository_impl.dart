import '../../core/stream_utils.dart';
import '../../domain/net_worth.dart';
import '../../domain/repositories/net_worth_repository.dart';
import '../../domain/repositories/position_repository.dart';
import '../dao/account_dao.dart';
import '../dao/transaction_dao.dart';

/// [NetWorthRepository] 的 Drift 实现：
/// 账户流 × 持仓估值流 × 交易流 → 资产总览（Dart 端回溯历史）。
class NetWorthRepositoryImpl implements NetWorthRepository {
  NetWorthRepositoryImpl(
    this._accountDao,
    this._transactionDao,
    this._positions, {
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final AccountDao _accountDao;
  final TransactionDao _transactionDao;
  final PositionRepository _positions;

  /// 当前时间注入点（测试固定"今天"，避免跨月边界抖动）。
  final DateTime Function() _now;

  @override
  Stream<AssetOverview> watchOverview({int months = 12}) {
    return combineLatest3(
      _accountDao.watchAccounts(),
      _positions.watchValuations(),
      _transactionDao.watchNetWorthInputs(),
      (accounts, valuations, txns) {
        final cash = cashLikeBalanceMinor(accounts);
        final investment = investmentValueMinor(valuations);
        final series = buildMonthlyNetWorthSeries(
          currentNetWorthMinor: cash + investment,
          transactions: txns,
          positions: [
            for (final v in valuations)
              NetWorthPosition(
                createdAt: v.position.createdAt,
                marketValueMinor: v.marketValueMinor ?? 0,
              ),
          ],
          accounts: [
            for (final a in accounts)
              if (cashLikeAccountTypes.contains(a.type))
                NetWorthAccount(
                  createdAt: a.createdAt,
                  balanceMinor: a.balanceMinor,
                ),
          ],
          anchor: _now(),
          months: months,
        );
        return AssetOverview(
          cashMinor: cash,
          investmentMinor: investment,
          investmentAccountBalanceMinor: investmentAccountBalanceMinor(
            accounts,
          ),
          unpricedPositionCount: unpricedPositionCount(valuations),
          series: series,
        );
      },
    );
  }
}
