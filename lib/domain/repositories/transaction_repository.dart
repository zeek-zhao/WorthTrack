import '../../../data/db/app_database.dart';
import '../../../data/dao/transaction_dao.dart';

/// 交易领域接口。
abstract class TransactionRepository {
  /// 监听最近交易（倒序）。
  Stream<List<Transaction>> watchRecent({int limit});

  /// 监听指定月份交易，可按账户/分类过滤。
  Stream<List<Transaction>> watchByMonth(
    DateTime month, {
    int? accountId,
    int? categoryId,
  });

  /// 记账并原子调整账户余额，返回交易 id。
  Future<int> addTransaction(NewTransaction input);

  /// 编辑交易并同步调整账户余额（冲销旧影响 + 应用新影响）。
  Future<void> updateTransaction(int txnId, NewTransaction input);

  /// 删除交易并回滚余额影响（幂等）。
  Future<void> deleteTransaction(int txnId);
}
