import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:worthtrack/core/money.dart';
import 'package:worthtrack/data/db/app_database.dart';
import 'package:worthtrack/data/dao/transaction_dao.dart';
import 'package:worthtrack/di.dart';

/// 记账/编辑对话框：支出、收入、转账三类。
///
/// [existing] 非空时为编辑模式（保存调用 updateTransaction）。
class TransactionEditDialog extends ConsumerStatefulWidget {
  const TransactionEditDialog({super.key, this.existing});

  final Transaction? existing;

  @override
  ConsumerState<TransactionEditDialog> createState() =>
      _TransactionEditDialogState();
}

class _TransactionEditDialogState extends ConsumerState<TransactionEditDialog> {
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  TxnType _type = TxnType.expense;
  int? _accountId;
  int? _toAccountId;
  int? _categoryId;
  String? _errorText;
  bool _initialized = false;

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  /// 首次拿到账户/分类列表后做一次初始化（编辑模式回填，新建模式选默认项）。
  void _initOnce(List<Account> accounts, List<Category> categories) {
    if (_initialized || accounts.isEmpty) {
      return;
    }
    _initialized = true;
    final existing = widget.existing;
    if (existing != null) {
      _type = existing.type;
      _accountId = existing.accountId;
      _toAccountId = existing.toAccountId;
      _categoryId = existing.categoryId;
      _amountController.text = Money.toYuan(existing.amountMinor);
      _noteController.text = existing.note ?? '';
    } else {
      _accountId = accounts.first.id;
      _toAccountId = accounts.length > 1 ? accounts.last.id : null;
      _syncCategoryDefault(categories);
    }
  }

  /// 类型切换后保证分类选择与新类型匹配。
  void _syncCategoryDefault(List<Category> categories) {
    final kind = _type == TxnType.expense
        ? CategoryKind.expense
        : CategoryKind.income;
    final candidates = categories.where((c) => c.kind == kind).toList();
    if (_categoryId != null && candidates.any((c) => c.id == _categoryId)) {
      return;
    }
    _categoryId = candidates.isEmpty ? null : candidates.first.id;
  }

  Future<void> _submit() async {
    final amountText = _amountController.text.trim();
    final amountMinor = Money.tryParseYuan(amountText);
    if (amountMinor == null || amountMinor == 0) {
      setState(() => _errorText = '请输入有效金额（最多两位小数）');
      return;
    }
    if (_accountId == null) {
      setState(() => _errorText = '请先在「资产」页创建账户');
      return;
    }
    if (_type == TxnType.transfer) {
      if (_toAccountId == null || _toAccountId == _accountId) {
        setState(() => _errorText = '转账目标账户必须与转出账户不同');
        return;
      }
    }
    final note = _noteController.text.trim();
    final input = NewTransaction(
      type: _type,
      accountId: _accountId!,
      toAccountId: _type == TxnType.transfer ? _toAccountId : null,
      categoryId: _type == TxnType.transfer ? null : _categoryId,
      amountMinor: amountMinor,
      note: note.isEmpty ? null : note,
      occurredAt: widget.existing?.occurredAt ?? DateTime.now(),
    );

    final repo = ref.read(transactionRepositoryProvider);
    if (widget.existing == null) {
      await repo.addTransaction(input);
    } else {
      await repo.updateTransaction(widget.existing!.id, input);
    }
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final accountRepo = ref.watch(accountRepositoryProvider);
    final categoryRepo = ref.watch(categoryRepositoryProvider);

    return AlertDialog(
      title: Text(widget.existing == null ? '记一笔' : '编辑交易'),
      content: SizedBox(
        width: 340,
        child: StreamBuilder<List<Account>>(
          stream: accountRepo.watchAccounts(),
          builder: (context, accSnap) {
            final accounts = accSnap.data ?? const <Account>[];
            return StreamBuilder<List<Category>>(
              stream: categoryRepo.watchAll(),
              builder: (context, catSnap) {
                final categories = catSnap.data ?? const <Category>[];
                _initOnce(accounts, categories);
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 类型选择
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final (type, label) in const [
                          (TxnType.expense, '支出'),
                          (TxnType.income, '收入'),
                          (TxnType.transfer, '转账'),
                        ])
                          ChoiceChip(
                            key: Key('txn_type_$label'),
                            label: Text(label),
                            selected: _type == type,
                            onSelected: (_) => setState(() {
                              _type = type;
                              _syncCategoryDefault(categories);
                            }),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('txn_amount_field'),
                      controller: _amountController,
                      autofocus: widget.existing == null,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: '金额（元）',
                        hintText: '如 25.80',
                      ),
                    ),
                    const SizedBox(height: 12),
                    // 账户选择
                    DropdownButtonFormField<int>(
                      key: const Key('txn_account_dropdown'),
                      initialValue: _accountId,
                      decoration: const InputDecoration(labelText: '账户'),
                      items: [
                        for (final a in accounts)
                          DropdownMenuItem<int>(
                            value: a.id,
                            child: Text(a.name),
                          ),
                      ],
                      onChanged: (v) => setState(() => _accountId = v),
                    ),
                    // 转账目标账户
                    if (_type == TxnType.transfer) ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                        key: const Key('txn_to_account_dropdown'),
                        initialValue: _toAccountId,
                        decoration: const InputDecoration(labelText: '转入账户'),
                        items: [
                          for (final a in accounts)
                            if (a.id != _accountId)
                              DropdownMenuItem<int>(
                                value: a.id,
                                child: Text(a.name),
                              ),
                        ],
                        onChanged: (v) => setState(() => _toAccountId = v),
                      ),
                    ],
                    // 分类（转账不适用）
                    if (_type != TxnType.transfer) ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                        key: const Key('txn_category_dropdown'),
                        initialValue: _categoryId,
                        decoration: const InputDecoration(labelText: '分类'),
                        items: [
                          for (final c in categories.where(
                            (c) =>
                                c.kind ==
                                (_type == TxnType.expense
                                    ? CategoryKind.expense
                                    : CategoryKind.income),
                          ))
                            DropdownMenuItem<int>(
                              value: c.id,
                              child: Text('${c.icon ?? ''}${c.name}'),
                            ),
                        ],
                        onChanged: (v) => setState(() => _categoryId = v),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('txn_note_field'),
                      controller: _noteController,
                      decoration: const InputDecoration(labelText: '备注（可选）'),
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
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('txn_save_btn'),
          onPressed: _submit,
          child: const Text('保存'),
        ),
      ],
    );
  }
}
