import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../data/db/app_database.dart';
import '../../di.dart';
import 'transaction_edit_dialog.dart';

/// 明细页：按月流水列表（按日分组、按账户/分类筛选）。
class TransactionsPage extends ConsumerStatefulWidget {
  const TransactionsPage({super.key});

  @override
  ConsumerState<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends ConsumerState<TransactionsPage> {
  DateTime _month = DateTime.now();
  int? _accountFilter;
  int? _categoryFilter;

  String _dayKey(DateTime t) => '${t.year}-${t.month}-${t.day}';

  String _dayLabel(DateTime t) =>
      '${t.month.toString().padLeft(2, '0')}月${t.day.toString().padLeft(2, '0')}日';

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(transactionRepositoryProvider);
    final accountRepo = ref.watch(accountRepositoryProvider);
    final categoryRepo = ref.watch(categoryRepositoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: () => setState(
                () => _month = DateTime(_month.year, _month.month - 1),
              ),
            ),
            Text('${_month.year}年${_month.month}月'),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: () => setState(
                () => _month = DateTime(_month.year, _month.month + 1),
              ),
            ),
          ],
        ),
        actions: [
          // 账户筛选
          StreamBuilder<List<Account>>(
            stream: accountRepo.watchAccounts(),
            builder: (context, snap) {
              final accounts = snap.data ?? const <Account>[];
              return DropdownButton<int?>(
                hint: const Text('全部账户'),
                value: _accountFilter,
                underline: const SizedBox.shrink(),
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('全部账户'),
                  ),
                  for (final a in accounts)
                    DropdownMenuItem<int?>(value: a.id, child: Text(a.name)),
                ],
                onChanged: (v) => setState(() => _accountFilter = v),
              );
            },
          ),
          const SizedBox(width: 8),
          // 分类筛选
          StreamBuilder<List<Category>>(
            stream: categoryRepo.watchAll(),
            builder: (context, snap) {
              final categories = snap.data ?? const <Category>[];
              return DropdownButton<int?>(
                hint: const Text('全部分类'),
                value: _categoryFilter,
                underline: const SizedBox.shrink(),
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('全部分类'),
                  ),
                  for (final c in categories)
                    DropdownMenuItem<int?>(value: c.id, child: Text(c.name)),
                ],
                onChanged: (v) => setState(() => _categoryFilter = v),
              );
            },
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: StreamBuilder<List<Transaction>>(
        stream: repo.watchByMonth(
          _month,
          accountId: _accountFilter,
          categoryId: _categoryFilter,
        ),
        builder: (context, snap) {
          final txns = snap.data ?? const <Transaction>[];
          if (txns.isEmpty) {
            return const Center(child: Text('本月暂无交易，点 + 记一笔'));
          }
          // 按日分组（流已按时间倒序）。
          final groups = <String, List<Transaction>>{};
          for (final t in txns) {
            groups.putIfAbsent(_dayKey(t.occurredAt), () => []).add(t);
          }
          final days = groups.keys.toList();
          return ListView.builder(
            key: const Key('txn_list'),
            itemCount: days.length,
            itemBuilder: (context, index) {
              final dayTxns = groups[days[index]]!;
              final dayNet = dayTxns.fold<int>(0, (sum, t) {
                return sum +
                    switch (t.type) {
                      TxnType.expense => -t.amountMinor,
                      TxnType.income => t.amountMinor,
                      TxnType.transfer => 0,
                    };
              });
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Row(
                      children: [
                        Text(
                          _dayLabel(dayTxns.first.occurredAt),
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const Spacer(),
                        Text(
                          dayNet == 0 ? '' : Money.toYuanSymbol(dayNet),
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ],
                    ),
                  ),
                  for (final t in dayTxns)
                    _TransactionTile(
                      transaction: t,
                      onLongPress: () => _showActions(context, t),
                    ),
                ],
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        key: const Key('add_txn_fab'),
        onPressed: () => _showEditDialog(context, null),
        tooltip: '记一笔',
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showEditDialog(BuildContext context, Transaction? existing) {
    showDialog<void>(
      context: context,
      builder: (_) => TransactionEditDialog(existing: existing),
    );
  }

  void _showActions(BuildContext context, Transaction t) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('编辑'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _showEditDialog(context, t);
              },
            ),
            ListTile(
              key: const Key('delete_txn_action'),
              leading: const Icon(Icons.delete_outline),
              title: const Text('删除'),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                final repo = ref.read(transactionRepositoryProvider);
                await repo.deleteTransaction(t.id);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _TransactionTile extends ConsumerWidget {
  const _TransactionTile({required this.transaction, this.onLongPress});

  final Transaction transaction;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = transaction;
    final accountRepo = ref.watch(accountRepositoryProvider);
    final categoryRepo = ref.watch(categoryRepositoryProvider);

    final (icon, amountText, amountColor) = switch (t.type) {
      TxnType.expense => (
        Icons.south_west,
        '-${Money.toYuan(t.amountMinor)}',
        Theme.of(context).colorScheme.onSurface,
      ),
      TxnType.income => (
        Icons.north_east,
        '+${Money.toYuan(t.amountMinor)}',
        const Color(0xFF2E7D32),
      ),
      TxnType.transfer => (
        Icons.swap_horiz,
        Money.toYuanSymbol(t.amountMinor),
        Theme.of(context).colorScheme.onSurface,
      ),
    };

    return FutureBuilder<(Account?, Category?, Account?)>(
      future: Future.wait([
        accountRepo.getById(t.accountId),
        if (t.categoryId != null)
          categoryRepo.getById(t.categoryId!)
        else
          Future<Category?>.value(),
        if (t.type == TxnType.transfer && t.toAccountId != null)
          accountRepo.getById(t.toAccountId!)
        else
          Future<Account?>.value(),
      ]).then((r) => (r[0] as Account?, r[1] as Category?, r[2] as Account?)),
      builder: (context, snap) {
        final accountName = snap.data?.$1?.name ?? '…';
        final cat = snap.data?.$2;
        final toName = snap.data?.$3?.name;
        final title = switch (t.type) {
          TxnType.transfer => '转账至 ${toName ?? '…'}',
          _ => t.note?.isNotEmpty == true ? t.note! : accountName,
        };
        return ListTile(
          key: Key('txn_${t.id}'),
          onLongPress: onLongPress,
          leading: Icon(icon, color: amountColor),
          title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            cat == null
                ? accountName
                : '${cat.icon ?? ''}${cat.name} · $accountName',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Text(
            amountText,
            style: TextStyle(
              color: amountColor,
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
        );
      },
    );
  }
}
