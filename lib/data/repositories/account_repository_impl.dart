import 'package:drift/drift.dart';

import '../dao/account_dao.dart';
import '../db/app_database.dart';
import '../../domain/repositories/account_repository.dart';

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
}
