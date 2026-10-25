import 'dart:async';

import 'package:worthtrack/data/dao/transaction_dao.dart';
import 'package:worthtrack/data/db/app_database.dart';
import 'package:worthtrack/domain/repositories/budget_repository.dart';
import 'package:worthtrack/domain/repositories/recurring_repository.dart';
import 'package:worthtrack/domain/repositories/category_repository.dart';
import 'package:worthtrack/domain/repositories/transaction_repository.dart';
import 'package:worthtrack/domain/stats.dart';

/// 每次订阅先回放当前值，再透传后续事件（解决广播流不缓存历史的问题）。
/// [src] 用动态类型以复用同一个 broadcast 控制器驱动多种结果类型。
Stream<T> replayStream<T>(T current, StreamController<dynamic> src) {
  late StreamController<T> out;
  out = StreamController<T>(onListen: () => out.add(current));
  src.stream.listen(
    (v) {
      if (v is T) {
        out.add(v);
      }
    },
    onDone: out.close,
    cancelOnError: true,
  );
  return out.stream;
}

/// 「变更源 + 计算函数」流：订阅时立即计算当前值，之后每次变更重新计算。
/// 假仓储用单一变更源驱动多种派生结果（快照/汇总/占比/趋势），类型互不污染。
Stream<T> valueStream<T>(T Function() compute, Stream<void> changes) {
  late StreamController<T> out;
  late StreamSubscription<void> sub;
  out = StreamController<T>(
    onListen: () {
      out.add(compute());
      sub = changes.listen((_) => out.add(compute()));
    },
    onPause: () => sub.pause(),
    onResume: () => sub.resume(),
    onCancel: () => sub.cancel(),
  );
  return out.stream;
}

/// 内存假交易仓储：记录调用，驱动 UI 测试。
class FakeTransactionRepository implements TransactionRepository {
  final _changes = StreamController<void>.broadcast();
  final added = <NewTransaction>[];
  final updated = <(int, NewTransaction)>[];
  final deletedIds = <int>[];
  List<Transaction> _txns = [];
  int _nextId = 1;

  /// 最近一次 watchByFilter 收到的过滤条件（供断言）。
  TxnFilter? lastFilter;

  void emit(List<Transaction> txns) {
    _txns = txns;
    _changes.add(null);
  }

  bool _match(Transaction t, TxnFilter f) {
    if (f.start != null && t.occurredAt.isBefore(f.start!)) {
      return false;
    }
    if (f.end != null && !t.occurredAt.isBefore(f.end!)) {
      return false;
    }
    if (f.type != null && t.type != f.type) {
      return false;
    }
    if (f.accountId != null &&
        t.accountId != f.accountId &&
        t.toAccountId != f.accountId) {
      return false;
    }
    if (f.categoryId != null && t.categoryId != f.categoryId) {
      return false;
    }
    if (f.keyword != null && f.keyword!.isNotEmpty) {
      final kw = f.keyword!;
      if ((t.note ?? '').contains(kw)) {
        return true;
      }
      // 分类名/账户名匹配在假仓储里不做（UI 测试只覆盖备注关键词）。
      return false;
    }
    return true;
  }

  @override
  Stream<List<Transaction>> watchRecent({int limit = 100}) => valueStream(() {
    final sorted = [..._txns]
      ..sort((x, y) => y.occurredAt.compareTo(x.occurredAt));
    return sorted.take(limit).toList();
  }, _changes.stream);

  @override
  Stream<List<Transaction>> watchByFilter(TxnFilter filter) {
    lastFilter = filter;
    return valueStream(
      () => _txns.where((t) => _match(t, filter)).toList(),
      _changes.stream,
    );
  }

  MonthTotals _sumRange(DateTime start, DateTime end, DateTime label) {
    var expense = 0;
    var income = 0;
    for (final t in _txns) {
      if (t.occurredAt.isBefore(start) || !t.occurredAt.isBefore(end)) {
        continue;
      }
      switch (t.type) {
        case TxnType.expense:
          expense += t.amountMinor;
        case TxnType.income:
          income += t.amountMinor;
        case TxnType.transfer:
          break;
      }
    }
    return MonthTotals(
      month: label,
      expenseMinor: expense,
      incomeMinor: income,
    );
  }

  @override
  Stream<MonthTotals> watchMonthTotals(DateTime month) => valueStream(
    () => _sumRange(
      DateTime(month.year, month.month),
      DateTime(month.year, month.month + 1),
      DateTime(month.year, month.month),
    ),
    _changes.stream,
  );

  @override
  Stream<MonthTotals> watchYearTotals(int year) => valueStream(
    () => _sumRange(DateTime(year), DateTime(year + 1), DateTime(year)),
    _changes.stream,
  );

  @override
  Stream<List<MonthTotals>> watchTrend({int months = 6, DateTime? anchor}) {
    final last = anchor ?? DateTime.now();
    return valueStream(() {
      final result = <MonthTotals>[];
      for (var i = months - 1; i >= 0; i--) {
        final m = DateTime(last.year, last.month - i);
        result.add(_sumRange(m, DateTime(m.year, m.month + 1), m));
      }
      return result;
    }, _changes.stream);
  }

  @override
  Stream<List<CategoryStat>> watchCategoryStats(
    DateTime month, {
    CategoryKind kind = CategoryKind.expense,
  }) => valueStream(
    () => _categoryStats(
      (t) =>
          t.occurredAt.year == month.year && t.occurredAt.month == month.month,
      kind,
    ),
    _changes.stream,
  );

  @override
  Stream<List<CategoryStat>> watchCategoryStatsRange(
    DateTime start,
    DateTime end, {
    CategoryKind kind = CategoryKind.expense,
  }) => valueStream(
    () => _categoryStats(
      (t) => !t.occurredAt.isBefore(start) && t.occurredAt.isBefore(end),
      kind,
    ),
    _changes.stream,
  );

  List<CategoryStat> _categoryStats(
    bool Function(Transaction) inRange,
    CategoryKind kind,
  ) {
    final map = <int?, CategoryStat>{};
    final wantType = kind == CategoryKind.expense
        ? TxnType.expense
        : TxnType.income;
    for (final t in _txns) {
      if (!inRange(t) || t.type != wantType) {
        continue;
      }
      final old = map[t.categoryId];
      map[t.categoryId] = CategoryStat(
        categoryId: t.categoryId,
        name: old?.name ?? '未分类',
        totalMinor: (old?.totalMinor ?? 0) + t.amountMinor,
        count: (old?.count ?? 0) + 1,
      );
    }
    return map.values.toList()
      ..sort((a, b) => b.totalMinor.compareTo(a.totalMinor));
  }

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

  void dispose() => _changes.close();
}

/// 内存假预算仓储。
class FakeBudgetRepository implements BudgetRepository {
  final _controller = StreamController<List<BudgetStatus>>.broadcast();
  final upserted = <(DateTime, int, int)>[]; // (month, categoryId, amountMinor)
  final deletedIds = <int>[];
  List<BudgetStatus> _statuses = [];

  void emit(List<BudgetStatus> statuses) {
    _statuses = statuses;
    _controller.add(statuses);
  }

  @override
  Stream<List<BudgetStatus>> watchBudgetStatuses(DateTime month) =>
      replayStream(_statuses, _controller);

  @override
  Future<void> upsertBudget(
    DateTime month, {
    required int categoryId,
    required int amountMinor,
  }) async {
    upserted.add((DateTime(month.year, month.month), categoryId, amountMinor));
  }

  @override
  Future<void> deleteBudget(int id) async {
    deletedIds.add(id);
    _statuses = _statuses.where((s) => s.budget.id != id).toList();
    _controller.add(_statuses);
  }

  void dispose() => _controller.close();
}

Budget makeTestBudget(
  int id, {
  required int categoryId,
  required int amountMinor,
  DateTime? month,
}) => Budget(
  id: id,
  categoryId: categoryId,
  amountMinor: amountMinor,
  month: month ?? DateTime(2026, 10),
  createdAt: DateTime(2026, 10, 1),
);

BudgetStatus makeTestBudgetStatus({
  required int categoryId,
  required String categoryName,
  required int amountMinor,
  required int spentMinor,
}) => BudgetStatus(
  budget: makeTestBudget(1, categoryId: categoryId, amountMinor: amountMinor),
  category: makeTestCategory(categoryId, categoryName, CategoryKind.expense),
  spentMinor: spentMinor,
);

/// 内存假周期账单仓储。
class FakeRecurringRepository implements RecurringRepository {
  final _controller = StreamController<List<RecurringRule>>.broadcast();
  final added = <Map<String, Object>>[];
  final deletedIds = <int>[];
  final toggles = <(int, bool)>[];
  int catchUpCalls = 0;
  List<RecurringRule> _rules = [];
  int _nextId = 1;

  void emit(List<RecurringRule> rules) {
    _rules = rules;
    _controller.add(rules);
  }

  @override
  Stream<List<RecurringRule>> watchRules({bool includeInactive = false}) =>
      replayStream(
        includeInactive ? _rules : _rules.where((r) => r.active).toList(),
        _controller,
      );

  @override
  Future<int> addRule({
    required String name,
    required TxnType type,
    required int accountId,
    int? categoryId,
    required int amountMinor,
    required RecurFrequency frequency,
    int interval = 1,
    required DateTime startDate,
    DateTime? endDate,
    String? note,
  }) async {
    added.add({
      'name': name,
      'type': type,
      'accountId': accountId,
      'amountMinor': amountMinor,
      'frequency': frequency,
    });
    return _nextId++;
  }

  @override
  Future<void> updateRule({
    required int id,
    String? name,
    int? accountId,
    int? categoryId,
    int? amountMinor,
    RecurFrequency? frequency,
    int? interval,
    DateTime? endDate,
    String? note,
  }) async {}

  @override
  Future<void> deleteRule(int id) async {
    deletedIds.add(id);
    emit(_rules.where((r) => r.id != id).toList());
  }

  @override
  Future<void> setActive(int id, bool active) async {
    toggles.add((id, active));
  }

  @override
  Future<int> catchUp(DateTime now) async {
    catchUpCalls++;
    return 0;
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
