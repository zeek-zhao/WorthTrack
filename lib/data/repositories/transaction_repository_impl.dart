import '../dao/transaction_dao.dart';
import '../db/app_database.dart';
import '../../domain/repositories/transaction_repository.dart';

/// [TransactionRepository] 的 Drift 实现。
class TransactionRepositoryImpl implements TransactionRepository {
  TransactionRepositoryImpl(this._dao);

  final TransactionDao _dao;

  @override
  Stream<List<Transaction>> watchRecent({int limit = 100}) =>
      _dao.watchRecent(limit: limit);

  @override
  Stream<List<Transaction>> watchByMonth(
    DateTime month, {
    int? accountId,
    int? categoryId,
  }) => _dao.watchByMonth(month, accountId: accountId, categoryId: categoryId);

  @override
  Future<int> addTransaction(NewTransaction input) =>
      _dao.createWithBalanceUpdate(input);

  @override
  Future<void> updateTransaction(int txnId, NewTransaction input) =>
      _dao.updateWithBalanceAdjust(txnId, input);

  @override
  Future<void> deleteTransaction(int txnId) =>
      _dao.deleteWithBalanceReversal(txnId);
}
