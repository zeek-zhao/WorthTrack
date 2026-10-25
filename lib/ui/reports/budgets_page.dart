import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../data/db/app_database.dart';
import '../../di.dart';
import '../../domain/stats.dart';

/// 预算管理页（issue #10）：按支出分类设置当月预算。
class BudgetsPage extends ConsumerStatefulWidget {
  const BudgetsPage({super.key});

  @override
  ConsumerState<BudgetsPage> createState() => _BudgetsPageState();
}

class _BudgetsPageState extends ConsumerState<BudgetsPage> {
  @override
  Widget build(BuildContext context) {
    final budgetRepo = ref.watch(budgetRepositoryProvider);
    final categoryRepo = ref.watch(categoryRepositoryProvider);
    final month = DateTime.now();

    return Scaffold(
      appBar: AppBar(title: const Text('月度预算')),
      body: StreamBuilder<List<BudgetStatus>>(
        stream: budgetRepo.watchBudgetStatuses(month),
        builder: (context, snap) {
          final statuses = snap.data ?? const <BudgetStatus>[];
          final statusByCat = <int, BudgetStatus>{
            for (final s in statuses) s.budget.categoryId: s,
          };
          return StreamBuilder<List<Category>>(
            stream: categoryRepo.watchAll(),
            builder: (context, catSnap) {
              final categories = (catSnap.data ?? const <Category>[])
                  .where((c) => c.kind == CategoryKind.expense)
                  .toList();
              if (categories.isEmpty) {
                return const Center(child: Text('暂无支出分类'));
              }
              return ListView(
                key: const Key('budget_list'),
                children: [
                  for (final c in categories)
                    _BudgetTile(
                      category: c,
                      status: statusByCat[c.id],
                      onTap: () => _editBudget(month, c, statusByCat[c.id]),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _editBudget(
    DateTime month,
    Category category,
    BudgetStatus? status,
  ) async {
    final controller = TextEditingController(
      text: status == null ? '' : Money.toYuan(status.budget.amountMinor),
    );
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${month.month}月「${category.name}」预算'),
        content: TextField(
          key: const Key('budget_amount_field'),
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: '每月预算（元）',
            hintText: '留空表示不设预算',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('budget_save_btn'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (saved != true) {
      return;
    }
    final text = controller.text.trim();
    final repo = ref.read(budgetRepositoryProvider);
    if (text.isEmpty) {
      // 留空 = 清除该分类预算。
      if (status != null) {
        await repo.deleteBudget(status.budget.id);
      }
    } else {
      final minor = Money.tryParseYuan(text);
      if (minor == null) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('金额无效，最多两位小数')));
        return;
      }
      await repo.upsertBudget(
        month,
        categoryId: category.id,
        amountMinor: minor,
      );
    }
  }
}

class _BudgetTile extends StatelessWidget {
  const _BudgetTile({required this.category, this.status, this.onTap});

  final Category category;
  final BudgetStatus? status;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = status;
    return ListTile(
      key: Key('budget_cat_${category.id}'),
      onTap: onTap,
      leading: Text(
        category.icon ?? '📦',
        style: const TextStyle(fontSize: 22),
      ),
      title: Text(category.name),
      subtitle: s == null
          ? const Text('未设置，点按设置')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.overBudget
                      ? '已用 ${Money.toYuanSymbol(s.spentMinor)}，超支 ${Money.toYuanSymbol(-s.remainingMinor)}'
                      : '已用 ${Money.toYuanSymbol(s.spentMinor)} / ${Money.toYuanSymbol(s.budget.amountMinor)}',
                  style: TextStyle(
                    color: s.overBudget
                        ? Theme.of(context).colorScheme.error
                        : null,
                  ),
                ),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: s.usage.clamp(0.0, 1.0),
                  color: s.overBudget
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context).colorScheme.primary,
                ),
              ],
            ),
      trailing: const Icon(Icons.edit_outlined, size: 18),
    );
  }
}
