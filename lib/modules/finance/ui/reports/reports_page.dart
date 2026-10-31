import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:worthtrack/core/money.dart';
import 'package:worthtrack/di.dart';
import 'package:worthtrack/modules/finance/domain/stats.dart';
import 'package:worthtrack/modules/finance/ui/recurring/recurring_page.dart';
import 'package:worthtrack/modules/finance/ui/reports/budgets_page.dart';

/// 饼图分类配色（循环取用）。
const _piePalette = [
  Color(0xFF2E7D32),
  Color(0xFF1976D2),
  Color(0xFFF57C00),
  Color(0xFF7B1FA2),
  Color(0xFF00838F),
  Color(0xFFC62828),
  Color(0xFF5D4037),
  Color(0xFF455A64),
];

/// 报表页（issue #9/#10）：月/年汇总、分类占比、趋势、预算状态。
class ReportsPage extends ConsumerStatefulWidget {
  const ReportsPage({super.key, this.initialMonth});

  /// 初始月份（测试注入用；生产默认当前月）。
  final DateTime? initialMonth;

  @override
  ConsumerState<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends ConsumerState<ReportsPage> {
  bool _yearMode = false;
  late DateTime _month = widget.initialMonth ?? DateTime.now();

  @override
  Widget build(BuildContext context) {
    final txnRepo = ref.watch(transactionRepositoryProvider);
    final budgetRepo = ref.watch(budgetRepositoryProvider);

    final totalsStream = _yearMode
        ? txnRepo.watchYearTotals(_month.year)
        : txnRepo.watchMonthTotals(_month);
    final trendAnchor = _yearMode ? DateTime(_month.year, 12) : _month;
    final trendMonths = _yearMode ? 12 : 6;
    final catStream = _yearMode
        ? txnRepo.watchCategoryStatsRange(
            DateTime(_month.year),
            DateTime(_month.year + 1),
          )
        : txnRepo.watchCategoryStats(_month);

    return Scaffold(
      appBar: AppBar(
        title: _yearMode
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () =>
                        setState(() => _month = DateTime(_month.year - 1)),
                  ),
                  Text('${_month.year}年'),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: () =>
                        setState(() => _month = DateTime(_month.year + 1)),
                  ),
                ],
              )
            : Row(
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
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'month', label: Text('月')),
              ButtonSegment(value: 'year', label: Text('年')),
            ],
            selected: {_yearMode ? 'year' : 'month'},
            onSelectionChanged: (s) =>
                setState(() => _yearMode = s.first == 'year'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        key: const Key('report_list'),
        padding: const EdgeInsets.all(12),
        children: [
          // 收支汇总卡
          StreamBuilder<MonthTotals>(
            stream: totalsStream,
            builder: (context, snap) {
              final t = snap.data;
              return Card(
                key: const Key('report_summary'),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _SummaryCell(
                        label: '收入',
                        value: t == null
                            ? '—'
                            : Money.toYuanSymbol(t.incomeMinor),
                        color: const Color(0xFF2E7D32),
                      ),
                      _SummaryCell(
                        label: '支出',
                        value: t == null
                            ? '—'
                            : Money.toYuanSymbol(t.expenseMinor),
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      _SummaryCell(
                        label: '结余',
                        value: t == null ? '—' : Money.toYuanSymbol(t.netMinor),
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          // 预算区（仅月模式）
          if (!_yearMode)
            StreamBuilder<List<BudgetStatus>>(
              stream: budgetRepo.watchBudgetStatuses(_month),
              builder: (context, snap) {
                final statuses = snap.data ?? const <BudgetStatus>[];
                return _BudgetCard(
                  month: _month,
                  statuses: statuses,
                  onManage: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const BudgetsPage(),
                    ),
                  ),
                );
              },
            ),
          // 分类占比
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _yearMode ? '全年支出分类占比' : '本月支出分类占比',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  StreamBuilder<List<CategoryStat>>(
                    stream: catStream,
                    builder: (context, snap) {
                      final stats = snap.data ?? const <CategoryStat>[];
                      if (stats.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(child: Text('暂无支出数据')),
                        );
                      }
                      return _CategoryPie(stats: stats);
                    },
                  ),
                ],
              ),
            ),
          ),
          // 趋势
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _yearMode ? '全年逐月趋势' : '近 6 个月趋势',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  StreamBuilder<List<MonthTotals>>(
                    stream: txnRepo.watchTrend(
                      months: trendMonths,
                      anchor: trendAnchor,
                    ),
                    builder: (context, snap) {
                      final totals = snap.data ?? const <MonthTotals>[];
                      if (totals.isEmpty) {
                        return const SizedBox.shrink();
                      }
                      return _TrendChart(totals: totals);
                    },
                  ),
                ],
              ),
            ),
          ),
          // 周期账单入口
          Card(
            child: ListTile(
              key: const Key('recurring_entry'),
              leading: const Icon(Icons.repeat),
              title: const Text('周期账单'),
              subtitle: const Text('房租、订阅等定期自动记账'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const RecurringPage()),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCell extends StatelessWidget {
  const _SummaryCell({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}

/// 预算卡：超支横幅 + 各预算进度条。
class _BudgetCard extends StatelessWidget {
  const _BudgetCard({
    required this.month,
    required this.statuses,
    required this.onManage,
  });

  final DateTime month;
  final List<BudgetStatus> statuses;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final overspent = statuses.where((s) => s.overBudget).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '${month.month}月预算',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                TextButton(onPressed: onManage, child: const Text('管理预算')),
              ],
            ),
            if (overspent.isNotEmpty)
              Container(
                key: const Key('budget_overspend_banner'),
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '⚠ 本月 ${overspent.length} 个分类超支：'
                  '${overspent.map((s) => s.category.name).join('、')}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            if (statuses.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('尚未设置预算，点「管理预算」开始'),
              )
            else
              for (final s in statuses)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('${s.category.icon ?? ''}${s.category.name}'),
                          const Spacer(),
                          Text(
                            s.overBudget
                                ? '已用 ${Money.toYuanSymbol(s.spentMinor)}，超支 ${Money.toYuanSymbol(-s.remainingMinor)}'
                                : '已用 ${Money.toYuanSymbol(s.spentMinor)} / ${Money.toYuanSymbol(s.budget.amountMinor)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: s.overBudget
                                  ? Theme.of(context).colorScheme.error
                                  : Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      LinearProgressIndicator(
                        value: s.usage.clamp(0.0, 1.0),
                        color: s.overBudget
                            ? Theme.of(context).colorScheme.error
                            : Theme.of(context).colorScheme.primary,
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

/// 分类占比：饼图 + 图例。
class _CategoryPie extends StatelessWidget {
  const _CategoryPie({required this.stats});

  final List<CategoryStat> stats;

  @override
  Widget build(BuildContext context) {
    final total = stats.fold<int>(0, (s, e) => s + e.totalMinor);
    final shown = stats.take(8).toList();
    return Column(
      children: [
        SizedBox(
          key: const Key('category_pie'),
          height: 180,
          child: PieChart(
            PieChartData(
              centerSpaceRadius: 40,
              sectionsSpace: 2,
              sections: [
                for (var i = 0; i < shown.length; i++)
                  PieChartSectionData(
                    value: shown[i].totalMinor.toDouble(),
                    title:
                        '${(shown[i].totalMinor * 100 / (total == 0 ? 1 : total)).round()}%',
                    radius: 44,
                    color: _piePalette[i % _piePalette.length],
                    titleStyle: const TextStyle(
                      fontSize: 11,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < shown.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: _piePalette[i % _piePalette.length],
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text('${shown[i].icon ?? ''}${shown[i].name}')),
                Text('${shown[i].count}笔'),
                const SizedBox(width: 12),
                Text(
                  '${Money.toYuanSymbol(shown[i].totalMinor)}'
                  '（${(shown[i].totalMinor * 100 / (total == 0 ? 1 : total)).toStringAsFixed(1)}%）',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 逐月趋势：双折线（支出/收入），横轴标签用图下方文字行实现，
/// 规避 fl_chart 不同版本标题 API 差异。
class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.totals});

  final List<MonthTotals> totals;

  @override
  Widget build(BuildContext context) {
    final maxV = totals.fold<int>(
      0,
      (m, t) =>
          [m, t.expenseMinor, t.incomeMinor].reduce((a, b) => a > b ? a : b),
    );
    final maxX = (totals.length - 1).toDouble();
    return Column(
      children: [
        SizedBox(
          height: 160,
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: maxX,
              minY: 0,
              maxY: maxV == 0 ? 100 : maxV * 1.15,
              gridData: const FlGridData(show: false),
              titlesData: const FlTitlesData(show: false),
              borderData: FlBorderData(show: false),
              lineTouchData: const LineTouchData(enabled: false),
              lineBarsData: [
                LineChartBarData(
                  spots: [
                    for (var i = 0; i < totals.length; i++)
                      FlSpot(i.toDouble(), totals[i].expenseMinor.toDouble()),
                  ],
                  isCurved: false,
                  barWidth: 2,
                  color: Theme.of(context).colorScheme.onSurface,
                  dotData: const FlDotData(show: false),
                ),
                LineChartBarData(
                  spots: [
                    for (var i = 0; i < totals.length; i++)
                      FlSpot(i.toDouble(), totals[i].incomeMinor.toDouble()),
                  ],
                  isCurved: false,
                  barWidth: 2,
                  color: const Color(0xFF2E7D32),
                  dotData: const FlDotData(show: false),
                ),
              ],
            ),
          ),
        ),
        Row(
          children: [
            for (final t in totals)
              Expanded(
                child: Center(
                  child: Text(
                    '${t.month.month}月',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _LegendDot(
              color: Theme.of(context).colorScheme.onSurface,
              label: '支出',
            ),
            const SizedBox(width: 16),
            const _LegendDot(color: Color(0xFF2E7D32), label: '收入'),
          ],
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, color: color),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}
