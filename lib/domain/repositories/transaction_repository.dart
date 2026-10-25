import '../../../data/db/app_database.dart';
import '../../../data/dao/transaction_dao.dart';

/// 交易领域接口。
abstract class TransactionRepository {
  /// 监听最近交易（倒序）。
  Stream<List<Transaction>> watchRecent({int limit});

  /// 监听指定月份交易。
  Stream<List<Transaction>> watchByMonth(DateTime month);

  /// 记账并原子调整账户余额，返回交易 id。
  Future<int> addTransaction(NewTransaction input);
}
