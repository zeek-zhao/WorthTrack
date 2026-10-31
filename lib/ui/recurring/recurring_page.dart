import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:worthtrack/core/money.dart';
import 'package:worthtrack/data/db/app_database.dart';
import 'package:worthtrack/di.dart';
import 'package:worthtrack/domain/recurring_logic.dart';

/// 周期账单页（issue #11）：规则列表 + 新建/编辑。
class RecurringPage extends ConsumerWidget {
  const RecurringPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(recurringRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('周期账单')),
      body: StreamBuilder<List<RecurringRule>>(
        stream: repo.watchRules(includeInactive: true),
        builder: (context, snap) {
          final rules = snap.data ?? const <RecurringRule>[];
          if (rules.isEmpty) {
            return const Center(child: Text('暂无周期账单，点 + 新建规则'));
          }
          return ListView(
            key: const Key('recurring_list'),
            children: [
              for (final r in rules)
                _RuleTile(
                  rule: r,
                  onTap: () => _showEditDialog(context, ref, r),
                ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        key: const Key('add_rule_fab'),
        tooltip: '新建周期账单',
        onPressed: () => _showEditDialog(context, ref, null),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showEditDialog(
    BuildContext context,
    WidgetRef ref,
    RecurringRule? existing,
  ) {
    showDialog<void>(
      context: context,
      builder: (_) => _RuleEditDialog(existing: existing),
    );
  }
}

class _RuleTile extends ConsumerWidget {
  const _RuleTile({required this.rule, this.onTap});

  final RecurringRule rule;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = rule;
    final freq =
        '${frequencyLabel(r.frequency)}${r.interval > 1 ? '（隔${r.interval}）' : ''}';
    final next = '${r.nextRunAt.month}月${r.nextRunAt.day}日';
    return ListTile(
      key: Key('rule_${r.id}'),
      onTap: onTap,
      leading: Icon(
        r.type == TxnType.income ? Icons.north_east : Icons.south_west,
        color: r.type == TxnType.income
            ? const Color(0xFF2E7D32)
            : Theme.of(context).colorScheme.onSurface,
      ),
      title: Text(
        r.name,
        style: r.active
            ? null
            : TextStyle(
                decoration: TextDecoration.lineThrough,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
      ),
      subtitle: Text('$freq · 下次 $next'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            Money.toYuanSymbol(r.amountMinor),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          Switch(
            key: Key('rule_switch_${r.id}'),
            value: r.active,
            onChanged: (v) =>
                ref.read(recurringRepositoryProvider).setActive(r.id, v),
          ),
        ],
      ),
      onLongPress: () async {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('删除周期账单'),
            content: Text('删除「${r.name}」？已生成的交易不受影响。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                key: const Key('rule_delete_confirm'),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('删除'),
              ),
            ],
          ),
        );
        if (confirmed == true) {
          await ref.read(recurringRepositoryProvider).deleteRule(r.id);
        }
      },
    );
  }
}

/// 规则新建/编辑对话框。
class _RuleEditDialog extends ConsumerStatefulWidget {
  const _RuleEditDialog({this.existing});

  final RecurringRule? existing;

  @override
  ConsumerState<_RuleEditDialog> createState() => _RuleEditDialogState();
}

class _RuleEditDialogState extends ConsumerState<_RuleEditDialog> {
  late final TextEditingController _name;
  late final TextEditingController _amount;
  late final TextEditingController _interval;
  late final TextEditingController _note;
  late TxnType _type;
  int? _accountId;
  int? _categoryId;
  late RecurFrequency _frequency;
  DateTime _startDate = DateTime.now();
  DateTime? _endDate;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final r = widget.existing;
    _name = TextEditingController(text: r?.name ?? '');
    _amount = TextEditingController(
      text: r == null ? '' : Money.toYuan(r.amountMinor),
    );
    _interval = TextEditingController(text: '${r?.interval ?? 1}');
    _note = TextEditingController(text: r?.note ?? '');
    _type = r?.type ?? TxnType.expense;
    _accountId = r?.accountId;
    _categoryId = r?.categoryId;
    _frequency = r?.frequency ?? RecurFrequency.monthly;
    _startDate = r?.startDate ?? DateTime.now();
    _endDate = r?.endDate;
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _interval.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart ? _startDate : (_endDate ?? _startDate);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
        } else {
          _endDate = picked;
        }
      });
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final minor = Money.tryParseYuan(_amount.text);
    final interval = int.tryParse(_interval.text.trim()) ?? 0;
    if (name.isEmpty || minor == null || minor <= 0 || interval < 1) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请填写名称、有效金额和 ≥1 的间隔')));
      return;
    }
    if (_accountId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请选择账户')));
      return;
    }
    final repo = ref.read(recurringRepositoryProvider);
    if (_isEdit) {
      await repo.updateRule(
        id: widget.existing!.id,
        name: name,
        accountId: _accountId,
        categoryId: _categoryId,
        amountMinor: minor,
        frequency: _frequency,
        interval: interval,
        endDate: _endDate,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      );
    } else {
      await repo.addRule(
        name: name,
        type: _type,
        accountId: _accountId!,
        categoryId: _categoryId,
        amountMinor: minor,
        frequency: _frequency,
        interval: interval,
        startDate: _startDate,
        endDate: _endDate,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      );
    }
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final accountRepo = ref.watch(accountRepositoryProvider);
    final categoryRepo = ref.watch(categoryRepositoryProvider);
    final kind = _type == TxnType.income
        ? CategoryKind.income
        : CategoryKind.expense;

    return AlertDialog(
      title: Text(_isEdit ? '编辑周期账单' : '新建周期账单'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!_isEdit)
              SegmentedButton<TxnType>(
                segments: const [
                  ButtonSegment(value: TxnType.expense, label: Text('支出')),
                  ButtonSegment(value: TxnType.income, label: Text('收入')),
                ],
                selected: {_type},
                onSelectionChanged: (s) => setState(() {
                  _type = s.first;
                  _categoryId = null;
                }),
              ),
            TextField(
              key: const Key('rule_name_field'),
              controller: _name,
              decoration: const InputDecoration(labelText: '名称（如：房租）'),
            ),
            TextField(
              key: const Key('rule_amount_field'),
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: '金额（元）'),
            ),
            StreamBuilder<List<Account>>(
              stream: accountRepo.watchAccounts(),
              builder: (context, snap) {
                final accounts = snap.data ?? const <Account>[];
                if (_accountId != null &&
                    accounts.every((a) => a.id != _accountId)) {
                  _accountId = null;
                }
                return InputDecorator(
                  decoration: const InputDecoration(labelText: '账户'),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      key: const Key('rule_account_dropdown'),
                      value: _accountId,
                      isDense: true,
                      hint: const Text('请选择'),
                      items: [
                        for (final a in accounts)
                          DropdownMenuItem<int>(
                            value: a.id,
                            child: Text(a.name),
                          ),
                      ],
                      onChanged: (v) => setState(() => _accountId = v),
                    ),
                  ),
                );
              },
            ),
            StreamBuilder<List<Category>>(
              stream: categoryRepo.watchAll(),
              builder: (context, snap) {
                final categories = (snap.data ?? const <Category>[])
                    .where((c) => c.kind == kind)
                    .toList();
                if (_categoryId != null &&
                    categories.every((c) => c.id != _categoryId)) {
                  _categoryId = null;
                }
                return InputDecorator(
                  decoration: const InputDecoration(labelText: '分类（可选）'),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      key: const Key('rule_category_dropdown'),
                      value: _categoryId,
                      isDense: true,
                      hint: const Text('请选择'),
                      items: [
                        for (final c in categories)
                          DropdownMenuItem<int>(
                            value: c.id,
                            child: Text('${c.icon ?? ''}${c.name}'),
                          ),
                      ],
                      onChanged: (v) => setState(() => _categoryId = v),
                    ),
                  ),
                );
              },
            ),
            Row(
              children: [
                Expanded(
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: '频率'),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<RecurFrequency>(
                        key: const Key('rule_frequency_dropdown'),
                        value: _frequency,
                        isDense: true,
                        items: [
                          for (final f in RecurFrequency.values)
                            DropdownMenuItem<RecurFrequency>(
                              value: f,
                              child: Text(frequencyLabel(f)),
                            ),
                        ],
                        onChanged: (v) => setState(() => _frequency = v!),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _interval,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '间隔（天/周/月/年）'),
                  ),
                ),
              ],
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('开始日期'),
              subtitle: Text(
                '${_startDate.year}-${_startDate.month}-${_startDate.day}',
              ),
              trailing: const Icon(Icons.calendar_today_outlined),
              onTap: () => _pickDate(isStart: true),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('结束日期（可选）'),
              subtitle: Text(
                _endDate == null
                    ? '无'
                    : '${_endDate!.year}-${_endDate!.month}-${_endDate!.day}',
              ),
              trailing: _endDate == null
                  ? const Icon(Icons.calendar_today_outlined)
                  : IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() => _endDate = null),
                    ),
              onTap: () => _pickDate(isStart: false),
            ),
            TextField(
              controller: _note,
              decoration: const InputDecoration(labelText: '备注（可选）'),
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
          key: const Key('rule_save_btn'),
          onPressed: _save,
          child: const Text('保存'),
        ),
      ],
    );
  }
}
