import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:worthtrack/core/money.dart';
import 'package:worthtrack/data/db/app_database.dart';
import 'package:worthtrack/modules/finance/data/dao/transaction_dao.dart';
import 'package:worthtrack/di.dart';
import 'package:worthtrack/modules/finance/ui/transactions/transaction_edit_dialog.dart';

/// 明细页：按月流水列表，支持关键词搜索与类型/账户/分类组合筛选（issue #12）。
class TransactionsPage extends ConsumerStatefulWidget {
  const TransactionsPage({super.key});

  @override
  ConsumerState<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends ConsumerState<TransactionsPage> {
  DateTime _month = DateTime.now();
  TxnType? _typeFilter;
  int? _accountFilter;
  int? _categoryFilter;
  String _keyword = '';
  bool _showSearch = false;

  bool get _hasFilter =>
      _typeFilter != null ||
      _accountFilter != null ||
      _categoryFilter != null ||
      _keyword.isNotEmpty;

  String _dayKey(DateTime t) => '${t.year}-${t.month}-${t.day}';

  String _dayLabel(DateTime t) =>
      '${t.month.toString().padLeft(2, '0')}月${t.day.toString().padLeft(2, '0')}日';

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(transactionRepositoryProvider);

    final filter = TxnFilter(
      start: DateTime(_month.year, _month.month),
      end: DateTime(_month.year, _month.month + 1),
      type: _typeFilter,
      accountId: _accountFilter,
      categoryId: _categoryFilter,
      keyword: _keyword.isEmpty ? null : _keyword,
    );

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
          IconButton(
            key: const Key('search_toggle_btn'),
            icon: Icon(_showSearch ? Icons.search_off : Icons.search),
            tooltip: '搜索',
            onPressed: () => setState(() {
              _showSearch = !_showSearch;
              if (!_showSearch) {
                _keyword = '';
              }
            }),
          ),
          IconButton(
            key: const Key('filter_btn'),
            icon: Badge(
              isLabelVisible: _hasFilter,
              child: const Icon(Icons.tune),
            ),
            tooltip: '筛选',
            onPressed: _openFilterSheet,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          if (_showSearch)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: TextField(
                key: const Key('search_field'),
                autofocus: false,
                decoration: const InputDecoration(
                  hintText: '搜索备注 / 分类 / 账户',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _keyword = v.trim()),
              ),
            ),
          if (_hasFilter)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                children: [
                  const Icon(Icons.tune, size: 16),
                  const SizedBox(width: 4),
                  const Text('筛选中'),
                  const Spacer(),
                  TextButton(
                    key: const Key('clear_filter_btn'),
                    onPressed: () => setState(() {
                      _typeFilter = null;
                      _accountFilter = null;
                      _categoryFilter = null;
                      _keyword = '';
                    }),
                    child: const Text('清除筛选'),
                  ),
                ],
              ),
            ),
          Expanded(
            child: StreamBuilder<List<Transaction>>(
              stream: repo.watchByFilter(filter),
              builder: (context, snap) {
                final txns = snap.data ?? const <Transaction>[];
                if (txns.isEmpty) {
                  return Center(
                    child: Text(_hasFilter ? '没有符合条件的交易' : '本月暂无交易，点 + 记一笔'),
                  );
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
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        key: const Key('add_txn_fab'),
        onPressed: () => _showEditDialog(context, null),
        tooltip: '记一笔',
        child: const Icon(Icons.add),
      ),
    );
  }

  /// 组合筛选底部弹层：类型/账户/分类，确认后应用。
  Future<void> _openFilterSheet() async {
    final accountRepo = ref.read(accountRepositoryProvider);
    final categoryRepo = ref.read(categoryRepositoryProvider);
    var type = _typeFilter;
    var accountId = _accountFilter;
    var categoryId = _categoryFilter;

    final result = await showModalBottomSheet<(TxnType?, int?, int?)>(
      context: context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('交易类型'),
                SegmentedButton<TxnType?>(
                  segments: const [
                    ButtonSegment<TxnType?>(value: null, label: Text('全部')),
                    ButtonSegment<TxnType?>(
                      value: TxnType.expense,
                      label: Text('支出'),
                    ),
                    ButtonSegment<TxnType?>(
                      value: TxnType.income,
                      label: Text('收入'),
                    ),
                    ButtonSegment<TxnType?>(
                      value: TxnType.transfer,
                      label: Text('转账'),
                    ),
                  ],
                  selected: {type},
                  onSelectionChanged: (s) =>
                      setSheetState(() => type = s.first),
                ),
                const SizedBox(height: 12),
                StreamBuilder<List<Account>>(
                  stream: accountRepo.watchAccounts(),
                  builder: (context, snap) {
                    final accounts = snap.data ?? const <Account>[];
                    return InputDecorator(
                      decoration: const InputDecoration(labelText: '账户'),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int?>(
                          value: accountId,
                          isDense: true,
                          items: [
                            const DropdownMenuItem<int?>(
                              value: null,
                              child: Text('全部账户'),
                            ),
                            for (final a in accounts)
                              DropdownMenuItem<int?>(
                                value: a.id,
                                child: Text(a.name),
                              ),
                          ],
                          onChanged: (v) => setSheetState(() => accountId = v),
                        ),
                      ),
                    );
                  },
                ),
                StreamBuilder<List<Category>>(
                  stream: categoryRepo.watchAll(),
                  builder: (context, snap) {
                    final categories = snap.data ?? const <Category>[];
                    return InputDecorator(
                      decoration: const InputDecoration(labelText: '分类'),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int?>(
                          value: categoryId,
                          isDense: true,
                          items: [
                            const DropdownMenuItem<int?>(
                              value: null,
                              child: Text('全部分类'),
                            ),
                            for (final c in categories)
                              DropdownMenuItem<int?>(
                                value: c.id,
                                child: Text(c.name),
                              ),
                          ],
                          onChanged: (v) => setSheetState(() => categoryId = v),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    TextButton(
                      key: const Key('sheet_reset_btn'),
                      onPressed: () => setSheetState(() {
                        type = null;
                        accountId = null;
                        categoryId = null;
                      }),
                      child: const Text('重置'),
                    ),
                    const Spacer(),
                    FilledButton(
                      key: const Key('sheet_apply_btn'),
                      onPressed: () => Navigator.of(
                        sheetContext,
                      ).pop((type, accountId, categoryId)),
                      child: const Text('应用'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (result != null) {
      setState(() {
        _typeFilter = result.$1;
        _accountFilter = result.$2;
        _categoryFilter = result.$3;
      });
    }
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
