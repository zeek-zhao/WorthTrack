import 'package:drift/drift.dart';

import 'account_dao.dart';
import '../db/app_database.dart';

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

  /// 监听指定月份的交易（按 occurredAt 的年月过滤，左闭右开区间）。
  ///
  /// [accountId] / [categoryId] 非空时追加过滤；转账交易的 toAccountId
  /// 也参与账户过滤（转入账户视角可见）。
  Stream<List<Transaction>> watchByMonth(
    DateTime month, {
    int? accountId,
    int? categoryId,
  }) {
    final start = DateTime(month.year, month.month);
    final end = DateTime(month.year, month.month + 1);
    return (select(transactions)
          ..where(
            (t) =>
                t.occurredAt.isBiggerOrEqualValue(start) &
                t.occurredAt.isSmallerThanValue(end) &
                (accountId == null
                    ? const Constant(true)
                    : t.accountId.equals(accountId) |
                          t.toAccountId.equalsNullable(accountId)) &
                (categoryId == null
                    ? const Constant(true)
                    : t.categoryId.equalsNullable(categoryId)),
          )
          ..orderBy([
            (t) => OrderingTerm.desc(t.occurredAt),
            (t) => OrderingTerm.desc(t.id),
          ]))
        .watch();
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
