import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:worthtrack/core/module/app_module.dart';
import 'package:worthtrack/core/module/module_providers.dart';
import 'package:worthtrack/core/module/module_registry.dart';

/// 首页 launcher：模块九宫格 + 常驻快捷动作。
///
/// 它**不认识任何具体模块**：模块卡片来自注册表，快捷动作来自各模块的
/// `quickActions`，所以停用/新增模块都不需要改这个文件。
class LauncherPage extends ConsumerWidget {
  const LauncherPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 首次加载（DB 还没回）时先按「全部启用」渲染，避免闪一下空列表。
    // Riverpod 3 里 `AsyncValue.value` 就是可空的，不再有 `valueOrNull`。
    final enabled =
        ref.watch(enabledModuleIdsProvider).value ??
        {for (final module in appModules) module.id};
    final modules = modulesByOrder(
      appModules,
    ).where((m) => enabled.contains(m.id)).toList();
    final shortcuts = [
      for (final module in modules) ...module.quickActions(context),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('WorthTrack'),
        actions: [
          IconButton(
            key: const Key('launcher-settings'),
            tooltip: '设置',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (shortcuts.isNotEmpty) ...[
            Wrap(spacing: 12, runSpacing: 12, children: shortcuts),
            const SizedBox(height: 20),
          ],
          if (modules.isEmpty)
            const _EmptyHint()
          else
            GridView.count(
              crossAxisCount: MediaQuery.sizeOf(context).width >= 600 ? 3 : 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.15,
              children: [for (final m in modules) _ModuleCard(module: m)],
            ),
        ],
      ),
    );
  }
}

class _ModuleCard extends StatelessWidget {
  const _ModuleCard({required this.module});

  final AppModule module;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: Key('launcher-module-${module.id}'),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.go('/${module.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(module.icon, size: 28, color: theme.colorScheme.primary),
              Text(
                module.name,
                style: theme.textTheme.titleMedium,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 48),
      child: Column(
        children: [
          Icon(
            Icons.widgets_outlined,
            size: 48,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 12),
          const Text('所有模块都停用了，去设置里重新启用'),
        ],
      ),
    );
  }
}
