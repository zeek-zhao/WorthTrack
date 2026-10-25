import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../data/db/app_database.dart';
import '../../di.dart';

/// 账户类型的中文展示名。
const _typeLabels = <AccountType, String>{
  AccountType.cash: '现金',
  AccountType.bank: '储蓄卡',
  AccountType.credit: '信用卡',
  AccountType.investment: '投资账户',
};

/// 资产页：账户列表 + 总资产 + 建账户入口。
///
/// 数据全部来自 Repository 的 Drift Watch 流，余额变化自动刷新。
class AccountsPage extends ConsumerWidget {
  const AccountsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 直接订阅仓储的 Watch 流，余额变化自动刷新。
    final repo = ref.watch(accountRepositoryProvider);
    final accountsStream = repo.watchAccounts();
    final totalStream = repo.watchTotalBalanceMinor();

    return Scaffold(
      appBar: AppBar(title: const Text('WorthTrack')),
      body: StreamBuilder<int>(
        stream: totalStream,
        builder: (context, totalSnap) {
          final total = totalSnap.data;
          return StreamBuilder<List<Account>>(
            stream: accountsStream,
            builder: (context, snap) {
              final accounts = snap.data ?? const <Account>[];
              return CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(child: _TotalCard(total: total)),
                  SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final account = accounts[index];
                      return ListTile(
                        leading: Text(
                          _typeLabels[account.type] ?? '?',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                        title: Text(account.name),
                        subtitle: account.note == null
                            ? null
                            : Text(account.note!),
                        trailing: Text(
                          Money.toYuanSymbol(account.balanceMinor),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      );
                    }, childCount: accounts.length),
                  ),
                ],
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        key: const Key('add_account_fab'),
        onPressed: () => _showAddDialog(context),
        tooltip: '新建账户',
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showAddDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => const _AddAccountDialog(),
    );
  }
}

class _TotalCard extends StatelessWidget {
  const _TotalCard({this.total});

  final int? total;

  @override
  Widget build(BuildContext context) {
    final total = this.total;
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('总资产', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 4),
            Text(
              total == null ? '…' : Money.toYuanSymbol(total),
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _AddAccountDialog extends ConsumerStatefulWidget {
  const _AddAccountDialog();

  @override
  ConsumerState<_AddAccountDialog> createState() => _AddAccountDialogState();
}

class _AddAccountDialogState extends ConsumerState<_AddAccountDialog> {
  final _nameController = TextEditingController();
  final _balanceController = TextEditingController();
  AccountType _type = AccountType.cash;
  String? _errorText;

  @override
  void dispose() {
    _nameController.dispose();
    _balanceController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _errorText = '请输入账户名');
      return;
    }
    final balanceText = _balanceController.text.trim();
    final initialMinor = balanceText.isEmpty
        ? 0
        : Money.tryParseYuan(balanceText);
    if (balanceText.isNotEmpty && initialMinor == null) {
      setState(() => _errorText = '金额格式：最多两位小数，如 123.45');
      return;
    }
    await ref
        .read(accountRepositoryProvider)
        .createAccount(
          name: name,
          type: _type,
          initialBalanceMinor: initialMinor ?? 0,
        );
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('新建账户'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('account_name_field'),
              controller: _nameController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '账户名',
                hintText: '如：微信零钱',
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final entry in _typeLabels.entries)
                  ChoiceChip(
                    key: Key('type_${entry.value}'),
                    label: Text(entry.value),
                    selected: _type == entry.key,
                    onSelected: (_) => setState(() => _type = entry.key),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('account_balance_field'),
              controller: _balanceController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: '初始余额（元，可留空）',
                hintText: '如 1234.56',
              ),
            ),
            if (_errorText != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _errorText!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('account_save_btn'),
          onPressed: _submit,
          child: const Text('保存'),
        ),
      ],
    );
  }
}
