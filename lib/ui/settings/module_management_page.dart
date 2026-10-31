import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:worthtrack/core/module/app_module.dart';
import 'package:worthtrack/core/module/module_data_cleaner.dart';
import 'package:worthtrack/core/module/module_providers.dart';
import 'package:worthtrack/core/module/module_registry.dart';
import 'package:worthtrack/ui/settings/settings_section.dart';

/// 模块管理页（issue #45）。
///
/// 四个动作，**启用/停用与清理是两条完全不同的路径**：
/// - 启用 / 停用：只改 `module_state.enabled`，业务数据一行不动；
/// - 清理数据：物理删除该模块 `ownedTables` 里的所有行，不可恢复。
///
/// 这一页挂在 `/settings/modules` 下，是 **core 路由**，不受模块开关影响——
/// 停用全部模块之后，用户仍然能回到这里把它们重新打开（#45 的防死锁硬约束）。
class ModuleManagementPage extends ConsumerStatefulWidget {
  const ModuleManagementPage({super.key, this.modules = appModules});

  /// 要管理的模块，默认是全局注册表。测试注入假模块用。
  final List<AppModule> modules;

  @override
  ConsumerState<ModuleManagementPage> createState() =>
      _ModuleManagementPageState();
}

class _ModuleManagementPageState extends ConsumerState<ModuleManagementPage> {
  /// 正在执行动作的模块，避免连点造成并发写。
  final Set<ModuleId> _busy = <ModuleId>{};

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _setBusy(ModuleId id, Future<void> Function() action) async {
    if (_busy.contains(id)) return;
    setState(() => _busy.add(id));
    try {
      await action();
    } catch (error) {
      _toast('操作失败：$error');
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  Future<void> _toggle(AppModule module, bool enable) {
    return _setBusy(module.id, () async {
      final repo = ref.read(moduleStateRepositoryProvider);
      final context = ref.read(moduleContextProvider);
      if (enable) {
        await module.onEnable(context);
      } else {
        await module.onDisable(context);
      }
      await repo.setEnabled(module.id, enable);
      _toast(enable ? '已启用「${module.name}」' : '已停用「${module.name}」，数据未删除');
    });
  }

  Future<void> _clear(AppModule module) async {
    final cleaner = ref.read(moduleDataCleanerProvider);
    final counts = await cleaner.countRows(module.ownedTables);
    if (!mounted) return;

    final total = counts.values.fold(0, (sum, value) => sum + value);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('module_clear_dialog'),
        title: Text('清理「${module.name}」的数据？'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(describeRowCounts(counts, labels: module.tableLabels)),
            const SizedBox(height: 12),
            const Text(
              '将永久删除这个模块的全部数据，无法撤销。'
              '建议先在「备份与恢复」里导出一份备份。',
              style: TextStyle(color: Colors.red),
            ),
            const SizedBox(height: 8),
            Text(
              '模块本身保持${_isEnabled(module.id) ? '启用' : '停用'}状态；'
              '想连入口一起隐藏，请用「停用」。',
              style: Theme.of(dialogContext).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            key: const Key('module_clear_cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('module_clear_confirm'),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('永久删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await _setBusy(module.id, () async {
      final removed = await ref
          .read(moduleDataCleanerProvider)
          .clearModule(module, ref.read(moduleContextProvider));
      _toast(total == 0 ? '没有可清理的数据' : '已删除 $removed 条记录');
    });
  }

  Future<void> _move(List<AppModule> modules, int index, int delta) {
    final target = index + delta;
    if (target < 0 || target >= modules.length) return Future<void>.value();
    final reordered = List<AppModule>.of(modules);
    final moved = reordered.removeAt(index);
    reordered.insert(target, moved);

    return _setBusy(moved.id, () async {
      final orders = <ModuleId, int>{
        for (var i = 0; i < reordered.length; i++) reordered[i].id: i,
      };
      await ref.read(moduleStateRepositoryProvider).setSortOrders(orders);
    });
  }

  bool _isEnabled(ModuleId id) {
    final enabled = ref.read(enabledModuleIdsProvider).value;
    return enabled == null || enabled.contains(id);
  }

  @override
  Widget build(BuildContext context) {
    final all = widget.modules;
    final enabled =
        ref.watch(enabledModuleIdsProvider).value ??
        {for (final module in all) module.id};
    final orders = ref.watch(moduleSortOrdersProvider).value ?? const {};
    final modules = orderModules(all, orders);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('模块管理')),
      body: modules.isEmpty
          ? const Center(child: Text('没有注册任何模块'))
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              children: [
                const SettingsHint(
                  '「停用」只是把模块从首页隐藏，数据一条都不会删；'
                  '「清理数据」才会真正删除，且无法撤销。',
                ),
                for (var i = 0; i < modules.length; i++)
                  _ModuleCard(
                    module: modules[i],
                    enabled: enabled.contains(modules[i].id),
                    busy: _busy.contains(modules[i].id),
                    isFirst: i == 0,
                    isLast: i == modules.length - 1,
                    onToggle: (value) => _toggle(modules[i], value),
                    onClear: () => _clear(modules[i]),
                    onMoveUp: () => _move(modules, i, -1),
                    onMoveDown: () => _move(modules, i, 1),
                    subtitleColor: theme.colorScheme.onSurfaceVariant,
                  ),
              ],
            ),
    );
  }
}

class _ModuleCard extends StatelessWidget {
  const _ModuleCard({
    required this.module,
    required this.enabled,
    required this.busy,
    required this.isFirst,
    required this.isLast,
    required this.onToggle,
    required this.onClear,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.subtitleColor,
  });

  final AppModule module;
  final bool enabled;
  final bool busy;
  final bool isFirst;
  final bool isLast;
  final ValueChanged<bool> onToggle;
  final VoidCallback onClear;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final Color subtitleColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: Key('module_tile_${module.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  module.icon,
                  color: enabled
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outline,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(module.name, style: theme.textTheme.titleMedium),
                      Text(
                        enabled ? '已启用' : '已停用 · 数据仍保留',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: enabled
                              ? theme.colorScheme.primary
                              : subtitleColor,
                        ),
                      ),
                    ],
                  ),
                ),
                // 排序：上下移动一格，写回 module_state.sort_order。
                IconButton(
                  key: Key('module_up_${module.id}'),
                  tooltip: '上移',
                  onPressed: isFirst || busy ? null : onMoveUp,
                  icon: const Icon(Icons.keyboard_arrow_up),
                ),
                IconButton(
                  key: Key('module_down_${module.id}'),
                  tooltip: '下移',
                  onPressed: isLast || busy ? null : onMoveDown,
                  icon: const Icon(Icons.keyboard_arrow_down),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                TextButton.icon(
                  key: Key('module_clear_${module.id}'),
                  onPressed: busy ? null : onClear,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('清理数据'),
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                  ),
                ),
                const Spacer(),
                Text(
                  enabled ? '启用' : '停用',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: subtitleColor,
                  ),
                ),
                Switch(
                  key: Key('module_switch_${module.id}'),
                  value: enabled,
                  onChanged: busy ? null : onToggle,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
