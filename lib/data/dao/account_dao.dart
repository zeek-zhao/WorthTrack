import 'package:drift/drift.dart';

import '../db/app_database.dart';

part 'account_dao.g.dart';

/// 账户表 DAO。
@DriftAccessor(tables: [Accounts])
class AccountDao extends DatabaseAccessor<AppDatabase> with _$AccountDaoMixin {
  AccountDao(super.db);

  /// 监听全部账户（默认不含归档，按 sortOrder、id 排序）。
  Stream<List<Account>> watchAccounts({bool includeArchived = false}) {
    final query = select(accounts);
    if (!includeArchived) {
      query.where((a) => a.archivedAt.isNull());
    }
    query.orderBy([
      (a) => OrderingTerm.asc(a.sortOrder),
      (a) => OrderingTerm.asc(a.id),
    ]);
    return query.watch();
  }

  Future<Account?> getById(int id) {
    return (select(accounts)..where((a) => a.id.equals(id))).getSingleOrNull();
  }

  Future<int> createAccount(AccountsCompanion entry) {
    return into(accounts).insert(entry);
  }

  /// 归档账户（软删除）。
  Future<void> archiveAccount(int id) {
    return (update(accounts)..where((a) => a.id.equals(id))).write(
      AccountsCompanion(archivedAt: Value(DateTime.now())),
    );
  }

  /// 将账户余额调整为 [newBalanceMinor]（调用方需保证在事务内）。
  Future<void> setBalance(int accountId, int newBalanceMinor) {
    return (update(accounts)..where((a) => a.id.equals(accountId))).write(
      AccountsCompanion(balanceMinor: Value(newBalanceMinor)),
    );
  }
}
