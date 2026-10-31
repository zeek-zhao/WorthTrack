import 'package:drift/drift.dart';

import 'package:worthtrack/modules/finance/data/dao/account_dao.dart';
import 'package:worthtrack/data/db/app_database.dart';
import 'package:worthtrack/modules/finance/domain/repositories/account_repository.dart';

/// [AccountRepository] 的 Drift 实现。
class AccountRepositoryImpl implements AccountRepository {
  AccountRepositoryImpl(this._dao);

  final AccountDao _dao;

  @override
  Stream<List<Account>> watchAccounts() => _dao.watchAccounts();

  @override
  Future<Account?> getById(int id) => _dao.getById(id);

  @override
  Future<int> createAccount({
    required String name,
    required AccountType type,
    int initialBalanceMinor = 0,
    String? note,
  }) {
    return _dao.createAccount(
      AccountsCompanion.insert(
        name: name,
        type: type,
        balanceMinor: Value(initialBalanceMinor),
        note: Value(note),
      ),
    );
  }

  @override
  Future<void> archiveAccount(int id) => _dao.archiveAccount(id);

  @override
  Future<void> updateAccount({
    required int id,
    String? name,
    String? note,
    int? sortOrder,
  }) {
    final companion = AccountsCompanion(
      name: name == null ? const Value.absent() : Value(name),
      note: note == null ? const Value.absent() : Value(note),
      sortOrder: sortOrder == null ? const Value.absent() : Value(sortOrder),
    );
    return _dao.updateAccount(id, companion);
  }

  @override
  Future<void> unarchiveAccount(int id) => _dao.unarchiveAccount(id);

  @override
  Stream<int> watchTotalBalanceMinor() => _dao.watchTotalBalanceMinor();

  @override
  Stream<Map<AccountType, int>> watchBalanceByType() =>
      _dao.watchBalanceByType();
}
