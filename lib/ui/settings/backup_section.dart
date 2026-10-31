import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:worthtrack/core/providers.dart';
import 'package:worthtrack/core/backup/backup.dart';
import 'package:worthtrack/ui/settings/settings_section.dart';

/// 设置页「备份与恢复」分组（issue #18）。
///
/// 交互顺序刻意是「先体检、再确认、最后覆盖」：
/// 选完文件先 `inspect`，把「不是备份 / 版本不对 / 文件损坏」挡在确认框之前，
/// 用户不会在点了「覆盖并恢复」之后才发现文件根本用不了。
class BackupSection extends ConsumerStatefulWidget {
  const BackupSection({super.key});

  @override
  ConsumerState<BackupSection> createState() => _BackupSectionState();
}

class _BackupSectionState extends ConsumerState<BackupSection> {
  /// 导出/恢复进行中，避免重复点击。
  bool _busy = false;

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _onExport() async {
    final repo = ref.read(backupRepositoryProvider);
    final picker = ref.read(fileSavePickerProvider);
    setState(() => _busy = true);
    try {
      final bytes = await repo.exportBytes();
      if (!mounted) return;
      final savedPath = await picker.saveBytes(
        suggestedName: buildBackupFileName(DateTime.now()),
        bytes: bytes,
      );
      if (savedPath == null) return; // 用户取消，不打扰
      _toast('已导出备份（${formatFileSize(bytes.length)}）');
    } catch (_) {
      _toast('导出失败，请重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onRestore() async {
    final repo = ref.read(backupRepositoryProvider);
    final picker = ref.read(fileSavePickerProvider);

    final path = await picker.pickFileToRead();
    if (path == null || !mounted) return;

    setState(() => _busy = true);
    late final BackupInspection inspection;
    try {
      inspection = await repo.inspect(path);
    } catch (_) {
      if (mounted) setState(() => _busy = false);
      _toast('读取备份文件失败');
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);

    if (!inspection.canRestore) {
      await _showProblem(inspection.problem!);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _RestoreConfirmDialog(inspection: inspection),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await repo.restoreFrom(path);
      _toast(
        '已恢复备份：${inspection.accountCount} 个账户、'
        '${inspection.transactionCount} 条流水',
      );
    } catch (_) {
      // 恢复是单事务，失败即整体回滚，所以可以放心这么承诺。
      _toast('恢复失败，当前数据没有被改动');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showProblem(BackupProblem problem) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('backup_problem_dialog'),
        title: const Text('无法恢复这份备份'),
        content: Text(problem.message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SettingsSectionHeader('备份与恢复'),
        ListTile(
          key: const Key('backup_export_tile'),
          leading: const Icon(Icons.save_alt),
          title: const Text('导出备份'),
          subtitle: const Text('把整个账本存成一个文件，可拷到电脑或网盘'),
          enabled: !_busy,
          onTap: _busy ? null : _onExport,
        ),
        ListTile(
          key: const Key('backup_restore_tile'),
          leading: const Icon(Icons.settings_backup_restore),
          title: const Text('从备份恢复'),
          subtitle: const Text('用备份文件覆盖当前账本，恢复前会再确认一次'),
          enabled: !_busy,
          onTap: _busy ? null : _onRestore,
        ),
        const SettingsHint(
          '备份文件是完整的账本数据库，包含账户、流水、分类、预算、周期账单、'
          '持仓与行情缓存；不包含 PIN（PIN 只和这台设备有关）。'
          '换手机时先导出、在新手机上恢复即可。',
        ),
        const Divider(height: 1),
      ],
    );
  }
}

/// 恢复前的二次确认：把「会覆盖什么」「备份里有什么」都摊开写清楚。
class _RestoreConfirmDialog extends StatelessWidget {
  const _RestoreConfirmDialog({required this.inspection});

  final BackupInspection inspection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final detailStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return AlertDialog(
      key: const Key('backup_confirm_dialog'),
      title: const Text('覆盖当前账本？'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '当前账本里的全部数据会被这份备份替换，'
            '而且无法撤销。建议先导出一份备份再继续。',
          ),
          const SizedBox(height: 12),
          Text(inspection.fileName, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 4),
          Text(
            '${formatFileSize(inspection.sizeBytes)} · '
            '${inspection.accountCount} 个账户 · '
            '${inspection.transactionCount} 条流水 · '
            '${inspection.positionCount} 只持仓',
            style: detailStyle,
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('backup_cancel_btn'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        TextButton(
          key: const Key('backup_confirm_btn'),
          onPressed: () => Navigator.of(context).pop(true),
          style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
          child: const Text('覆盖并恢复'),
        ),
      ],
    );
  }
}
