import '../../../data/db/app_database.dart';

/// 账户领域接口：UI 层只依赖此抽象，不直接触碰 Drift。
abstract class AccountRepository {
  /// 监听使用中的账户（不含归档）。
  Stream<List<Account>> watchAccounts();

  /// 按 id 查询，不存在返回 null。
  Future<Account?> getById(int id);

  /// 新建账户，返回 id。余额以分为单位。
  Future<int> createAccount({
    required String name,
    required AccountType type,
    int initialBalanceMinor = 0,
    String? note,
  });

  /// 软删除（归档）账户。
  Future<void> archiveAccount(int id);
}
