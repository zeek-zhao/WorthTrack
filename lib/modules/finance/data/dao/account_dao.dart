import 'package:drift/drift.dart';

import 'package:worthtrack/data/db/app_database.dart';

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

  /// 更新账户基本信息（名称/备注/排序）。
  Future<void> updateAccount(int id, AccountsCompanion entry) {
    return (update(accounts)..where((a) => a.id.equals(id))).write(entry);
  }

  /// 恢复归档账户。
  Future<void> unarchiveAccount(int id) {
    return (update(accounts)..where((a) => a.id.equals(id))).write(
      const AccountsCompanion(archivedAt: Value(null)),
    );
  }

  /// 监听总资产：所有未归档账户余额之和（实时）。
  Stream<int> watchTotalBalanceMinor() {
    final sum = accounts.balanceMinor.sum();
    final query = selectOnly(accounts)
      ..addColumns([sum])
      ..where(accounts.archivedAt.isNull());
    return query.watchSingle().map((row) => row.read(sum) ?? 0);
  }

  /// 监听各类型账户的余额汇总（未归档，实时）。
  ///
  /// 账户表行数很小，Dart 端聚合即可；避免 selectOnly 与
  /// type converter（GeneratedColumnWithTypeConverter）的兼容问题。
  Stream<Map<AccountType, int>> watchBalanceByType() {
    final query = select(accounts)..where((a) => a.archivedAt.isNull());
    return query.watch().map((rows) {
      final map = <AccountType, int>{};
      for (final a in rows) {
        map[a.type] = (map[a.type] ?? 0) + a.balanceMinor;
      }
      return map;
    });
  }
}
