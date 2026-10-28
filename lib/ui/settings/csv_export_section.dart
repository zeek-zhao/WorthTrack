import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di.dart';
import '../../domain/csv_export.dart';
import 'settings_section.dart';

/// 设置页「数据导出」分组（issue #19）：把全部流水导成 CSV 给 Excel 用。
///
/// 与备份分开摆，因为两者用途不同：备份是「出事能还原」，CSV 是「拿去算/存档」。
class CsvExportSection extends ConsumerStatefulWidget {
  const CsvExportSection({super.key});

  @override
  ConsumerState<CsvExportSection> createState() => _CsvExportSectionState();
}

class _CsvExportSectionState extends ConsumerState<CsvExportSection> {
  bool _busy = false;

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _onExport() async {
    final repo = ref.read(exportRepositoryProvider);
    final picker = ref.read(fileSavePickerProvider);
    setState(() => _busy = true);
    try {
      final now = DateTime.now();
      final export = await repo.transactionsCsv();
      if (!mounted) return;
      final savedPath = await picker.saveBytes(
        suggestedName: buildCsvFileName(now),
        bytes: export.bytes,
      );
      if (savedPath == null) return; // 用户取消，不打扰
      _toast('已导出 ${export.rowCount} 条流水（CSV）');
    } catch (_) {
      _toast('导出失败，请重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SettingsSectionHeader('数据导出'),
        ListTile(
          key: const Key('csv_export_tile'),
          leading: const Icon(Icons.table_view_outlined),
          title: const Text('导出流水（CSV）'),
          subtitle: const Text('UTF-8 编码，Excel / WPS / Numbers 双击就能打开'),
          enabled: !_busy,
          onTap: _busy ? null : _onExport,
        ),
        const SettingsHint(
          '导出全部流水，列顺序为：时间、类型、账户、分类、金额（元）、备注。'
          '转账的账户列写成「转出 → 转入」。CSV 只是一份副本，'
          '要还原账本请用上面的「备份与恢复」。',
        ),
        const Divider(height: 1),
      ],
    );
  }
}
