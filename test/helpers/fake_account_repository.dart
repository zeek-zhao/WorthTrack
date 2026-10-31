import 'dart:async';

import 'package:worthtrack/data/db/app_database.dart';
import 'package:worthtrack/modules/finance/domain/repositories/account_repository.dart';

import 'fake_transaction_repository.dart' show replayStream;

/// 内存假实现：驱动 UI 测试，不依赖数据库。
class FakeAccountRepository implements AccountRepository {
  final _controller = StreamController<List<Account>>.broadcast();
  List<Account> _accounts = [];
  int _nextId = 1;

  /// 推送最新账户列表到所有订阅者。
  void emit(List<Account> accounts) {
    _accounts = accounts;
    _controller.add(accounts);
  }

  /// 账户变更广播源（供假净资产仓储联动重算）。
  Stream<List<Account>> get changes => _controller.stream;

  /// 当前账户列表（假净资产仓储按它推算总览）。
  List<Account> get current => _accounts;

  @override
  Stream<List<Account>> watchAccounts() => replayStream(_accounts, _controller);

  @override
  Future<Account?> getById(int id) async {
    for (final a in _accounts) {
      if (a.id == id) return a;
    }
    return null;
  }

  @override
  Future<int> createAccount({
    required String name,
    required AccountType type,
    int initialBalanceMinor = 0,
    String? note,
  }) async {
    final account = Account(
      id: _nextId++,
      name: name,
      type: type,
      balanceMinor: initialBalanceMinor,
      note: note,
      sortOrder: 0,
      archivedAt: null,
      createdAt: DateTime(2026, 10, 25),
    );
    emit([..._accounts, account]);
    return account.id;
  }

  @override
  Future<void> updateAccount({
    required int id,
    String? name,
    String? note,
    int? sortOrder,
  }) async {}

  @override
  Future<void> archiveAccount(int id) async {}

  @override
  Future<void> unarchiveAccount(int id) async {}

  @override
  Stream<int> watchTotalBalanceMinor() => watchAccounts().map(
    (list) => list.fold<int>(0, (sum, a) => sum + a.balanceMinor),
  );

  @override
  Stream<Map<AccountType, int>> watchBalanceByType() =>
      watchAccounts().map((list) {
        final map = <AccountType, int>{};
        for (final a in list) {
          map[a.type] = (map[a.type] ?? 0) + a.balanceMinor;
        }
        return map;
      });

  void dispose() => _controller.close();
}

/// 构造测试用账户数据类。
Account makeTestAccount(
  int id,
  String name,
  AccountType type,
  int balanceMinor,
) => Account(
  id: id,
  name: name,
  type: type,
  balanceMinor: balanceMinor,
  note: null,
  sortOrder: 0,
  archivedAt: null,
  createdAt: DateTime(2026, 10, 25),
);
