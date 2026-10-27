import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../data/db/app_database.dart';
import '../../di.dart';
import '../../domain/position_valuation.dart';
import '../../domain/repositories/position_repository.dart';

/// A 股习惯：涨红跌绿。
const _upColor = Color(0xFFEF5350);
const _downColor = Color(0xFF4CAF50);

/// 投资持仓页：持仓列表 + 组合汇总 + 新建/编辑/改价/归档/删除 + 手动刷新行情。
///
/// 现价来源：手动录入（写 price_cache）或行情刷新覆盖（M3-#14）；
/// M3-#15 补「拉取失败回退缓存价 + 更新时间标注」。
class PositionsPage extends ConsumerStatefulWidget {
  const PositionsPage({super.key});

  @override
  ConsumerState<PositionsPage> createState() => _PositionsPageState();
}

class _PositionsPageState extends ConsumerState<PositionsPage> {
  bool _refreshing = false;

  Future<void> _refreshQuotes() async {
    setState(() => _refreshing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final report = await ref.read(positionRepositoryProvider).refreshPrices();
      messenger.showSnackBar(SnackBar(content: Text(report.summary)));
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(positionRepositoryProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('投资持仓'),
        actions: [
          IconButton(
            key: const Key('refresh_prices_btn'),
            tooltip: '刷新行情',
            onPressed: _refreshing ? null : _refreshQuotes,
            icon: _refreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: StreamBuilder<List<PositionValuation>>(
        stream: repo.watchValuations(),
        builder: (context, snap) {
          final list = snap.data ?? const <PositionValuation>[];
          if (list.isEmpty) {
            return const Center(child: Text('暂无持仓，点 + 添加'));
          }
          final summary = PortfolioSummary.from(list);
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _SummaryCard(summary: summary)),
              SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  return _PositionTile(valuation: list[index]);
                }, childCount: list.length),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        key: const Key('add_position_fab'),
        tooltip: '新建持仓',
        onPressed: () => _openEditDialog(context),
        child: const Icon(Icons.add),
      ),
    );
  }
}

void _openEditDialog(BuildContext context, [PositionValuation? initial]) {
  showDialog<void>(
    context: context,
    builder: (_) => _PositionDialog(initial: initial),
  );
}

/// 盈亏文案：`+¥150.00（+6.25%）`；无现价时 `—`。
String _profitText(int? profitMinor, double? percent) {
  if (profitMinor == null) return '—';
  final sign = profitMinor > 0 ? '+' : '';
  final pct = percent == null
      ? '—'
      : '${percent > 0 ? '+' : ''}${percent.toStringAsFixed(2)}%';
  return '$sign${Money.toYuanSymbol(profitMinor)}（$pct）';
}

Color? _profitColor(int? profitMinor) {
  if (profitMinor == null || profitMinor == 0) return null;
  return profitMinor > 0 ? _upColor : _downColor;
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});

  final PortfolioSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasPrice = summary.pricedCount > 0;
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('持仓市值', style: theme.textTheme.labelMedium),
            const SizedBox(height: 4),
            Text(
              hasPrice ? Money.toYuanSymbol(summary.marketValueMinor) : '—',
              style: theme.textTheme.headlineMedium,
            ),
            const SizedBox(height: 6),
            Text(
              hasPrice
                  ? '总成本 ${Money.toYuanSymbol(summary.costMinor)} · '
                        '盈亏 ${_profitText(summary.profitMinor, summary.profitPercent)}'
                  : '共 ${summary.totalCount} 只，均未录价',
              style: theme.textTheme.labelMedium?.copyWith(
                color: _profitColor(summary.profitMinor),
              ),
            ),
            if (hasPrice && summary.unpricedCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '另有 ${summary.unpricedCount} 只未录价，暂不计入市值',
                  style: theme.textTheme.labelSmall,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PositionTile extends ConsumerWidget {
  const _PositionTile({required this.valuation});

  final PositionValuation valuation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final position = valuation.position;
    final marketValue = valuation.marketValueMinor;
    final profit = valuation.profitMinor;
    return ListTile(
      key: Key('position_${valuation.symbol}'),
      onTap: () => _openEditDialog(context, valuation),
      title: Row(
        children: [
          Flexible(
            child: Text(
              position.name,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${marketLabel(position.market)}${position.code}',
            style: theme.textTheme.labelSmall,
          ),
        ],
      ),
      subtitle: Text(
        '份额 ${formatShares(position.sharesCent)} · '
        '成本 ${Money.toYuanSymbol(position.costPriceMinor)}',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                marketValue == null ? '待录价' : Money.toYuanSymbol(marketValue),
                style: theme.textTheme.titleSmall,
              ),
              Text(
                _profitText(profit, valuation.profitPercent),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: _profitColor(profit),
                ),
              ),
            ],
          ),
          IconButton(
            key: Key('position_menu_${valuation.symbol}'),
            tooltip: '更多',
            icon: const Icon(Icons.more_vert),
            onPressed: () => _showActions(context, ref, valuation),
          ),
        ],
      ),
    );
  }

  Future<void> _showActions(
    BuildContext context,
    WidgetRef ref,
    PositionValuation valuation,
  ) {
    final repo = ref.read(positionRepositoryProvider);
    return showModalBottomSheet<void>(
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
                _openEditDialog(context, valuation);
              },
            ),
            ListTile(
              key: const Key('archive_position_btn'),
              leading: const Icon(Icons.inventory_2_outlined),
              title: const Text('归档（清仓）'),
              subtitle: const Text('不再计入市值，历史价格保留'),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                await repo.archivePosition(valuation.position.id);
              },
            ),
            ListTile(
              key: const Key('delete_position_btn'),
              leading: const Icon(Icons.delete_outline),
              title: const Text('删除'),
              subtitle: const Text('录错时使用，不可恢复'),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                final confirmed = await _confirmDelete(context);
                if (confirmed) {
                  await repo.deletePosition(valuation.position.id);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除持仓'),
        content: Text('确认删除「${valuation.position.name}」？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('confirm_delete_position_btn'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}

/// 新建 / 编辑持仓对话框。
///
/// 编辑时市场与代码只读（换股票请删除后重建，避免与唯一键冲突语义混淆）。
class _PositionDialog extends ConsumerStatefulWidget {
  const _PositionDialog({this.initial});

  final PositionValuation? initial;

  @override
  ConsumerState<_PositionDialog> createState() => _PositionDialogState();
}

class _PositionDialogState extends ConsumerState<_PositionDialog> {
  late final TextEditingController _codeController;
  late final TextEditingController _nameController;
  late final TextEditingController _sharesController;
  late final TextEditingController _costController;
  late final TextEditingController _priceController;
  late Market _market;
  String? _errorText;

  bool get _isEdit => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _market = initial?.position.market ?? Market.sh;
    _codeController = TextEditingController(text: initial?.position.code ?? '');
    _nameController = TextEditingController(text: initial?.position.name ?? '');
    _sharesController = TextEditingController(
      text: initial == null ? '' : formatShares(initial.position.sharesCent),
    );
    _costController = TextEditingController(
      text: initial == null
          ? ''
          : Money.toYuan(initial.position.costPriceMinor),
    );
    final price = initial?.priceMinor;
    _priceController = TextEditingController(
      text: price == null ? '' : Money.toYuan(price),
    );
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _sharesController.dispose();
    _costController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _codeController.text.trim();
    final name = _nameController.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => _errorText = '代码需为 6 位数字');
      return;
    }
    if (name.isEmpty) {
      setState(() => _errorText = '请输入名称');
      return;
    }
    final sharesCent = tryParseSharesCent(_sharesController.text);
    if (sharesCent == null || sharesCent <= 0) {
      setState(() => _errorText = '份额需大于 0，最多两位小数');
      return;
    }
    final costMinor = Money.tryParseYuan(_costController.text);
    if (costMinor == null) {
      setState(() => _errorText = '成本价格式：最多两位小数，如 12.34');
      return;
    }
    final priceText = _priceController.text.trim();
    final priceMinor = priceText.isEmpty ? null : Money.tryParseYuan(priceText);
    if (priceText.isNotEmpty && priceMinor == null) {
      setState(() => _errorText = '现价格式：最多两位小数，如 12.34');
      return;
    }

    final repo = ref.read(positionRepositoryProvider);
    try {
      final initial = widget.initial;
      if (initial == null) {
        await repo.createPosition(
          market: _market,
          code: code,
          name: name,
          sharesCent: sharesCent,
          costPriceMinor: costMinor,
        );
        if (priceMinor != null) {
          await repo.setPrice(
            market: _market,
            code: code,
            priceMinor: priceMinor,
          );
        }
      } else {
        await repo.updatePosition(
          id: initial.position.id,
          name: name,
          sharesCent: sharesCent,
          costPriceMinor: costMinor,
        );
        if (priceMinor != null && priceMinor != initial.priceMinor) {
          await repo.setPrice(
            market: initial.position.market,
            code: initial.position.code,
            priceMinor: priceMinor,
          );
        }
      }
    } on PositionExistsException {
      if (!mounted) return;
      setState(() => _errorText = '该代码已在持仓中');
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEdit ? '编辑持仓' : '新建持仓'),
      content: SizedBox(
        width: 340,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                children: [
                  for (final market in Market.values)
                    ChoiceChip(
                      key: Key('market_${marketLabel(market)}'),
                      label: Text(marketLabel(market)),
                      selected: _market == market,
                      onSelected: _isEdit
                          ? null
                          : (_) => setState(() => _market = market),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('position_code_field'),
                controller: _codeController,
                enabled: !_isEdit,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '代码',
                  hintText: '6 位，如 600519 / 159915',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('position_name_field'),
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: '名称',
                  hintText: '如：贵州茅台',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('position_shares_field'),
                controller: _sharesController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: '持有份额',
                  hintText: '如 150 或 150.25',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('position_cost_field'),
                controller: _costController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: '成本价（元）',
                  hintText: '如 12.34',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('position_price_field'),
                controller: _priceController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: '现价（元，可留空）',
                  hintText: '留空则市值显示「待录价」',
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
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('position_save_btn'),
          onPressed: _submit,
          child: const Text('保存'),
        ),
      ],
    );
  }
}
