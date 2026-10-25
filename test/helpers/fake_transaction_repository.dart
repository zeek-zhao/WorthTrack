import 'dart:async';

import 'package:worthtrack/data/dao/transaction_dao.dart';
import 'package:worthtrack/data/db/app_database.dart';
import 'package:worthtrack/domain/repositories/category_repository.dart';
import 'package:worthtrack/domain/repositories/transaction_repository.dart';

/// 每次订阅先回放当前值，再透传后续事件（解决广播流不缓存历史的问题）。
Stream<T> replayStream<T>(T current, StreamController<T> src) {
  late StreamController<T> out;
  out = StreamController<T>(onListen: () => out.add(current));
  src.stream.listen(out.add, onDone: out.close, cancelOnError: true);
  return out.stream;
}

/// 内存假交易仓储：记录调用，驱动 UI 测试。
class FakeTransactionRepository implements TransactionRepository {
  final _controller = StreamController<List<Transaction>>.broadcast();
  final added = <NewTransaction>[];
  final updated = <(int, NewTransaction)>[];
  final deletedIds = <int>[];
  List<Transaction> _txns = [];
  int _nextId = 1;

  void emit(List<Transaction> txns) {
    _txns = txns;
    _controller.add(txns);
  }

  @override
  Stream<List<Transaction>> watchRecent({int limit = 100}) =>
      replayStream(_txns, _controller);

  @override
  Stream<List<Transaction>> watchByMonth(
    DateTime month, {
    int? accountId,
    int? categoryId,
  }) => replayStream(_txns, _controller);

  @override
  Future<int> addTransaction(NewTransaction input) async {
    added.add(input);
    final t = Transaction(
      id: _nextId++,
      type: input.type,
      accountId: input.accountId,
      toAccountId: input.toAccountId,
      categoryId: input.categoryId,
      amountMinor: input.amountMinor,
      note: input.note,
      occurredAt: input.occurredAt,
      createdAt: DateTime(2026, 10, 25),
    );
    emit([..._txns, t]);
    return t.id;
  }

  @override
  Future<void> updateTransaction(int txnId, NewTransaction input) async {
    updated.add((txnId, input));
  }

  @override
  Future<void> deleteTransaction(int txnId) async {
    deletedIds.add(txnId);
    emit(_txns.where((t) => t.id != txnId).toList());
  }

  void dispose() => _controller.close();
}

/// 内存假分类仓储。
class FakeCategoryRepository implements CategoryRepository {
  final _controller = StreamController<List<Category>>.broadcast();
  List<Category> _categories = [];
  int _nextId = 1;

  void emit(List<Category> categories) {
    _categories = categories;
    _controller.add(categories);
  }

  @override
  Stream<List<Category>> watchAll() => replayStream(_categories, _controller);

  @override
  Future<Category?> getById(int id) async {
    for (final c in _categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  @override
  Future<int> createCategory({
    required String name,
    required CategoryKind kind,
    String? icon,
    int? parentId,
    int sortOrder = 0,
  }) async {
    final c = Category(
      id: _nextId++,
      name: name,
      kind: kind,
      icon: icon,
      sortOrder: sortOrder,
      parentId: parentId,
      archivedAt: null,
    );
    emit([..._categories, c]);
    return c.id;
  }

  @override
  Future<void> updateCategory({
    required int id,
    String? name,
    String? icon,
    int? sortOrder,
  }) async {}

  @override
  Future<void> archiveCategory(int id) async {}

  @override
  Future<void> unarchiveCategory(int id) async {}

  @override
  Future<void> ensureSeeded() async {}

  void dispose() => _controller.close();
}

Category makeTestCategory(
  int id,
  String name,
  CategoryKind kind, {
  String? icon,
}) => Category(
  id: id,
  name: name,
  kind: kind,
  icon: icon,
  sortOrder: 0,
  parentId: null,
  archivedAt: null,
);

Transaction makeTestTransaction(
  int id, {
  required TxnType type,
  required int accountId,
  int? toAccountId,
  int? categoryId,
  required int amountMinor,
  String? note,
  DateTime? occurredAt,
}) => Transaction(
  id: id,
  type: type,
  accountId: accountId,
  toAccountId: toAccountId,
  categoryId: categoryId,
  amountMinor: amountMinor,
  note: note,
  occurredAt: occurredAt ?? DateTime(2026, 10, 25, 12),
  createdAt: DateTime(2026, 10, 25),
);
