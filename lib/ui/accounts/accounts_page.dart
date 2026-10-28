import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../data/db/app_database.dart';
import '../../di.dart';
import '../../domain/net_worth.dart';

/// 账户类型的中文展示名。
const _typeLabels = <AccountType, String>{
  AccountType.cash: '现金',
  AccountType.bank: '储蓄卡',
  AccountType.credit: '信用卡',
  AccountType.investment: '投资账户',
};

/// 资产页（issue #5 建账户 / issue #16 资产总览与净资产曲线）。
///
/// 结构：净资产卡片（含现金/投资拆分）→ 净资产走势 → 账户列表。
/// 数据全部来自 Repository 的 Drift Watch 流，余额或持仓变化自动刷新。
class AccountsPage extends ConsumerWidget {
  const AccountsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(accountRepositoryProvider);
    final overviewRepo = ref.watch(netWorthRepositoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('WorthTrack')),
      body: StreamBuilder<AssetOverview>(
        stream: overviewRepo.watchOverview(),
        builder: (context, overviewSnap) {
          final overview = overviewSnap.data;
          return StreamBuilder<List<Account>>(
            stream: repo.watchAccounts(),
            builder: (context, snap) {
              final accounts = snap.data ?? const <Account>[];
              return CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(child: _NetWorthCard(overview: overview)),
                  SliverToBoxAdapter(
                    child: _NetWorthTrendCard(series: overview?.series),
                  ),
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

/// 净资产卡片：总额 + 现金/投资拆分 + 口径提示。
class _NetWorthCard extends StatelessWidget {
  const _NetWorthCard({required this.overview});

  final AssetOverview? overview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = overview;
    return Card(
      key: const Key('net_worth_card'),
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('净资产', style: theme.textTheme.labelMedium),
            const SizedBox(height: 4),
            Text(
              data == null ? '…' : Money.toYuanSymbol(data.netWorthMinor),
              key: const Key('net_worth_value'),
              style: theme.textTheme.headlineMedium,
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _BreakdownCell(
                    key: const Key('cash_cell'),
                    label: '现金类',
                    value: data?.cashMinor,
                  ),
                ),
                Expanded(
                  child: _BreakdownCell(
                    key: const Key('investment_cell'),
                    label: '投资市值',
                    value: data?.investmentMinor,
                  ),
                ),
              ],
            ),
            if (data != null && data.unpricedPositionCount > 0)
              _HintText(
                key: const Key('unpriced_hint'),
                icon: Icons.info_outline,
                text: '${data.unpricedPositionCount} 只持仓未录价，市值未计入净资产',
              ),
            if (data != null && data.investmentAccountBalanceMinor != 0)
              _HintText(
                key: const Key('investment_account_hint'),
                icon: Icons.info_outline,
                text:
                    '投资账户余额 '
                    '${Money.toYuanSymbol(data.investmentAccountBalanceMinor)} '
                    '未计入（避免与持仓市值重复）',
              ),
          ],
        ),
      ),
    );
  }
}

class _BreakdownCell extends StatelessWidget {
  const _BreakdownCell({super.key, required this.label, required this.value});

  final String label;

  /// 单位：分；null 表示数据未就绪。
  final int? value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelSmall),
        const SizedBox(height: 2),
        Text(
          value == null ? '…' : Money.toYuanSymbol(value!),
          style: theme.textTheme.titleMedium,
        ),
      ],
    );
  }
}

class _HintText extends StatelessWidget {
  const _HintText({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 净资产走势卡片：近 N 个月折线 + 环比文案。
class _NetWorthTrendCard extends StatelessWidget {
  const _NetWorthTrendCard({required this.series});

  final List<NetWorthPoint>? series;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final points = series ?? const <NetWorthPoint>[];
    final change = formatSeriesChange(points);

    return Card(
      key: const Key('net_worth_trend_card'),
      margin: const EdgeInsets.symmetric(horizontal: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('净资产走势', style: theme.textTheme.titleMedium),
                const Spacer(),
                if (points.length >= 2)
                  Text(
                    '近 ${points.length} 个月',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (points.length < 2)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text(
                    '数据不足 2 个月，记账后自动生成曲线',
                    key: const Key('net_worth_chart_empty'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            else ...[
              SizedBox(height: 150, child: _NetWorthChart(series: points)),
              const SizedBox(height: 6),
              _MonthAxis(series: points),
              if (change != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    change,
                    key: const Key('net_worth_change'),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color:
                          points.last.netWorthMinor >=
                              points[points.length - 2].netWorthMinor
                          ? const Color(0xFFC62828)
                          : const Color(0xFF2E7D32),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 净资产折线：无坐标轴标题，横轴月份由 [_MonthAxis] 用文字行实现。
class _NetWorthChart extends StatelessWidget {
  const _NetWorthChart({required this.series});

  final List<NetWorthPoint> series;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final values = [for (final p in series) p.netWorthMinor];
    var minV = values.reduce(math.min);
    var maxV = values.reduce(math.max);
    if (maxV == minV) {
      // 全平（含全 0）：给固定高度，避免 fl_chart 退化。
      minV -= 10000;
      maxV += 10000;
    } else {
      final pad = math.max(((maxV - minV) * 0.12).round(), 1);
      minV -= pad;
      maxV += pad;
    }

    return LineChart(
      key: const Key('net_worth_chart'),
      LineChartData(
        minX: 0,
        maxX: (series.length - 1).toDouble(),
        minY: minV.toDouble(),
        maxY: maxV.toDouble(),
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < values.length; i++)
                FlSpot(i.toDouble(), values[i].toDouble()),
            ],
            isCurved: false,
            barWidth: 2,
            color: color,
            dotData: FlDotData(show: series.length <= 12),
            belowBarData: BarAreaData(
              show: true,
              color: color.withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
    );
  }
}

/// 月份标签行：点数多时隔位显示，避免挤在一起。
class _MonthAxis extends StatelessWidget {
  const _MonthAxis({required this.series});

  final List<NetWorthPoint> series;

  @override
  Widget build(BuildContext context) {
    final step = (series.length / 6).ceil().clamp(1, 12);
    return Row(
      children: [
        for (var i = 0; i < series.length; i++)
          Expanded(
            child: Center(
              child: Text(
                i % step == 0 || i == series.length - 1
                    ? '${series[i].month.month}月'
                    : '',
                style: Theme.of(context).textTheme.labelSmall,
                maxLines: 1,
                overflow: TextOverflow.clip,
              ),
            ),
          ),
      ],
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
