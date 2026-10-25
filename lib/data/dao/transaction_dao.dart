import 'package:drift/drift.dart';

import 'account_dao.dart';
import '../db/app_database.dart';
import '../../domain/stats.dart';

part 'transaction_dao.g.dart';

/// 新建交易所需字段（金额单位：分）。
class NewTransaction {
  const NewTransaction({
    required this.type,
    required this.accountId,
    this.toAccountId,
    this.categoryId,
    required this.amountMinor,
    this.note,
    required this.occurredAt,
  });

  final TxnType type;
  final int accountId;
  final int? toAccountId;
  final int? categoryId;
  final int amountMinor;
  final String? note;
  final DateTime occurredAt;
}

/// 交易组合过滤条件（issue #12）。
///
/// - [start] 含、[end] 不含（左闭右开，全项目时间过滤固定约定）
/// - [accountId] 同时匹配转出账户与转账目标账户
/// - [keyword] 对备注、分类名、账户名做包含匹配（LIKE %kw%）
class TxnFilter {
  const TxnFilter({
    this.start,
    this.end,
    this.type,
    this.accountId,
    this.categoryId,
    this.keyword,
  });

  final DateTime? start;
  final DateTime? end;
  final TxnType? type;
  final int? accountId;
  final int? categoryId;
  final String? keyword;
}

/// 交易表 DAO：写入交易与账户余额调整在**同一事务**内完成（碰钱路径）。
@DriftAccessor(tables: [Transactions, Accounts])
class TransactionDao extends DatabaseAccessor<AppDatabase>
    with _$TransactionDaoMixin {
  TransactionDao(super.db);

  /// 监听最近交易（倒序）。
  Stream<List<Transaction>> watchRecent({int limit = 100}) {
    return (select(transactions)
          ..orderBy([
            (t) => OrderingTerm.desc(t.occurredAt),
            (t) => OrderingTerm.desc(t.id),
          ])
          ..limit(limit))
        .watch();
  }

  /// 监听指定月份的交易（等价于 [watchByFilter] 的月份区间快捷方式）。
  Stream<List<Transaction>> watchByMonth(
    DateTime month, {
    int? accountId,
    int? categoryId,
  }) {
    return watchByFilter(
      TxnFilter(
        start: DateTime(month.year, month.month),
        end: DateTime(month.year, month.month + 1),
        accountId: accountId,
        categoryId: categoryId,
      ),
    );
  }

  /// 按组合条件过滤交易（关键词/类型/账户/分类/时间区间）。
  ///
  /// 联表 categories/accounts 仅为关键词匹配服务；返回行仍以
  /// transactions 表数据类为准。
  Stream<List<Transaction>> watchByFilter(TxnFilter f) {
    final query = select(transactions).join([
      leftOuterJoin(
        categories,
        categories.id.equalsExp(transactions.categoryId),
      ),
      leftOuterJoin(accounts, accounts.id.equalsExp(transactions.accountId)),
    ]);
    final t = transactions;
    Expression<bool> expr = const Constant(true);
    if (f.start != null) {
      expr = expr & t.occurredAt.isBiggerOrEqualValue(f.start!);
    }
    if (f.end != null) {
      expr = expr & t.occurredAt.isSmallerThanValue(f.end!);
    }
    if (f.type != null) {
      expr = expr & t.type.equalsValue(f.type!);
    }
    if (f.accountId != null) {
      expr =
          expr &
          (t.accountId.equals(f.accountId!) |
              t.toAccountId.equalsNullable(f.accountId));
    }
    if (f.categoryId != null) {
      expr = expr & t.categoryId.equalsNullable(f.categoryId);
    }
    if (f.keyword != null && f.keyword!.isNotEmpty) {
      final kw = '%${f.keyword!}%';
      expr =
          expr &
          (t.note.like(kw) | categories.name.like(kw) | accounts.name.like(kw));
    }
    query.where(expr);
    query.orderBy([
      OrderingTerm.desc(transactions.occurredAt),
      OrderingTerm.desc(transactions.id),
    ]);
    return query.watch().map(
      (rows) => rows.map((r) => r.readTable(transactions)).toList(),
    );
  }

  /// 监听指定月份收支汇总（转账不计入收支）。
  Stream<MonthTotals> watchMonthTotals(DateTime month) {
    final start = DateTime(month.year, month.month);
    return watchByFilter(
      TxnFilter(start: start, end: DateTime(month.year, month.month + 1)),
    ).map((txns) => _sumTotals(txns, start));
  }

  /// 监听整年收支汇总。
  Stream<MonthTotals> watchYearTotals(int year) {
    final start = DateTime(year);
    return watchByFilter(
      TxnFilter(start: start, end: DateTime(year + 1)),
    ).map((txns) => _sumTotals(txns, start));
  }

  /// 监听最近 [months] 个月（截至 [anchor] 当月，含）的逐月收支趋势。
  /// 跨年自动进位；无交易的月份补零，保证折线横轴完整。
  Stream<List<MonthTotals>> watchTrend({int months = 6, DateTime? anchor}) {
    final last = anchor ?? DateTime.now();
    final first = DateTime(last.year, last.month - (months - 1));
    final buckets = <DateTime, MonthTotals>{
      for (var i = 0; i < months; i++)
        DateTime(first.year, first.month + i): MonthTotals.zero(
          DateTime(first.year, first.month + i),
        ),
    };
    return watchByFilter(
      TxnFilter(start: first, end: DateTime(last.year, last.month + 1)),
    ).map((txns) {
      for (final t in txns) {
        final key = DateTime(t.occurredAt.year, t.occurredAt.month);
        final bucket = buckets[key];
        if (bucket == null) {
          continue;
        }
        switch (t.type) {
          case TxnType.expense:
            buckets[key] = MonthTotals(
              month: key,
              expenseMinor: bucket.expenseMinor + t.amountMinor,
              incomeMinor: bucket.incomeMinor,
            );
          case TxnType.income:
            buckets[key] = MonthTotals(
              month: key,
              expenseMinor: bucket.expenseMinor,
              incomeMinor: bucket.incomeMinor + t.amountMinor,
            );
          case TxnType.transfer:
            break;
        }
      }
      return buckets.values.toList(growable: false);
    });
  }

  /// 监听指定月份按分类聚合的统计（[kind] 决定统计支出还是收入），
  /// 金额降序。分类为空的交易归入「未分类」。
  Stream<List<CategoryStat>> watchCategoryStats(
    DateTime month, {
    CategoryKind kind = CategoryKind.expense,
  }) {
    return watchCategoryStatsRange(
      DateTime(month.year, month.month),
      DateTime(month.year, month.month + 1),
      kind: kind,
    );
  }

  /// [watchCategoryStats] 的任意区间版本（年度报表用）。
  Stream<List<CategoryStat>> watchCategoryStatsRange(
    DateTime start,
    DateTime end, {
    CategoryKind kind = CategoryKind.expense,
  }) {
    final query = select(transactions).join([
      leftOuterJoin(
        categories,
        categories.id.equalsExp(transactions.categoryId),
      ),
    ]);
    query.where(
      transactions.occurredAt.isBiggerOrEqualValue(start) &
          transactions.occurredAt.isSmallerThanValue(end) &
          transactions.type.equalsValue(
            kind == CategoryKind.expense ? TxnType.expense : TxnType.income,
          ),
    );
    return query.watch().map((rows) {
      final accs = <int?, _CategoryAcc>{};
      for (final row in rows) {
        final txn = row.readTable(transactions);
        final cat = row.readTableOrNull(categories);
        final acc = accs.putIfAbsent(
          cat?.id,
          () => _CategoryAcc(cat?.name ?? '未分类', cat?.icon),
        );
        acc.totalMinor += txn.amountMinor;
        acc.count++;
      }
      final stats =
          accs.entries
              .map(
                (e) => CategoryStat(
                  categoryId: e.key,
                  name: e.value.name,
                  icon: e.value.icon,
                  totalMinor: e.value.totalMinor,
                  count: e.value.count,
                ),
              )
              .toList()
            ..sort((a, b) => b.totalMinor.compareTo(a.totalMinor));
      return stats;
    });
  }

  MonthTotals _sumTotals(List<Transaction> txns, DateTime month) {
    var expense = 0;
    var income = 0;
    for (final t in txns) {
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
      month: month,
      expenseMinor: expense,
      incomeMinor: income,
    );
  }

  /// 写入一笔交易并同步调整账户余额（事务内原子完成）。
  ///
  /// - expense：账户余额减少
  /// - income：账户余额增加
  /// - transfer：转出账户减少、转入账户增加（要求 [NewTransaction.toAccountId] 非空）
  Future<int> createWithBalanceUpdate(NewTransaction input) {
    if (input.type == TxnType.transfer && input.toAccountId == null) {
      throw ArgumentError('transfer 必须指定 toAccountId');
    }
    return attachedDatabase.transaction(() async {
      final id = await into(transactions).insert(
        TransactionsCompanion.insert(
          type: input.type,
          accountId: input.accountId,
          amountMinor: input.amountMinor,
          occurredAt: input.occurredAt,
          toAccountId: Value(input.toAccountId),
          categoryId: Value(input.categoryId),
          note: Value(input.note),
        ),
      );
      final accDao = attachedDatabase.accountDao;
      await _applyEffect(accDao, input);
      return id;
    });
  }

  Future<void> _applyDelta(
    AccountDao accDao,
    int accountId,
    int deltaMinor,
  ) async {
    final acc = await accDao.getById(accountId);
    if (acc == null) {
      throw StateError('账户不存在: $accountId');
    }
    await accDao.setBalance(accountId, acc.balanceMinor + deltaMinor);
  }

  /// 更新交易并同步调整账户余额（事务内原子完成）。
  ///
  /// 先冲销旧交易对各账户的影响，再应用新交易的影响，最后更新行。
  Future<void> updateWithBalanceAdjust(int txnId, NewTransaction input) {
    if (input.type == TxnType.transfer && input.toAccountId == null) {
      throw ArgumentError('transfer 必须指定 toAccountId');
    }
    return attachedDatabase.transaction(() async {
      final old = await (select(
        transactions,
      )..where((t) => t.id.equals(txnId))).getSingleOrNull();
      if (old == null) {
        throw StateError('交易不存在: $txnId');
      }
      final accDao = attachedDatabase.accountDao;
      await _revert(accDao, old);
      await (update(transactions)..where((t) => t.id.equals(txnId))).write(
        TransactionsCompanion(
          type: Value(input.type),
          accountId: Value(input.accountId),
          toAccountId: Value(input.toAccountId),
          categoryId: Value(input.categoryId),
          amountMinor: Value(input.amountMinor),
          note: Value(input.note),
          occurredAt: Value(input.occurredAt),
        ),
      );
      await _applyEffect(accDao, input);
    });
  }

  /// 删除交易并回滚其对账户余额的影响（事务内原子完成）。
  Future<void> deleteWithBalanceReversal(int txnId) {
    return attachedDatabase.transaction(() async {
      final old = await (select(
        transactions,
      )..where((t) => t.id.equals(txnId))).getSingleOrNull();
      if (old == null) {
        return; // 幂等：不存在视为已删除。
      }
      final accDao = attachedDatabase.accountDao;
      await _revert(accDao, old);
      await (delete(transactions)..where((t) => t.id.equals(txnId))).go();
    });
  }

  /// 应用一笔新交易对余额的影响。
  Future<void> _applyEffect(AccountDao accDao, NewTransaction input) async {
    switch (input.type) {
      case TxnType.expense:
        await _applyDelta(accDao, input.accountId, -input.amountMinor);
      case TxnType.income:
        await _applyDelta(accDao, input.accountId, input.amountMinor);
      case TxnType.transfer:
        await _applyDelta(accDao, input.accountId, -input.amountMinor);
        await _applyDelta(accDao, input.toAccountId!, input.amountMinor);
    }
  }

  /// 冲销一笔已有交易对余额的影响（与 [_applyEffect] 完全互逆）。
  Future<void> _revert(AccountDao accDao, Transaction t) async {
    switch (t.type) {
      case TxnType.expense:
        await _applyDelta(accDao, t.accountId, t.amountMinor);
      case TxnType.income:
        await _applyDelta(accDao, t.accountId, -t.amountMinor);
      case TxnType.transfer:
        await _applyDelta(accDao, t.accountId, t.amountMinor);
        if (t.toAccountId != null) {
          await _applyDelta(accDao, t.toAccountId!, -t.amountMinor);
        }
    }
  }
}

/// 分类聚合的内部累加器。
class _CategoryAcc {
  _CategoryAcc(this.name, this.icon);

  final String name;
  final String? icon;
  int totalMinor = 0;
  int count = 0;
}
