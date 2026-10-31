import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worthtrack/core/backup/backup.dart';
import 'package:worthtrack/core/module/module_providers.dart';
import 'package:worthtrack/di.dart';
import 'package:worthtrack/modules/finance/domain/csv_export.dart';
import 'package:worthtrack/ui/settings/settings_page.dart';

import '../helpers/fake_backup_repository.dart';
import '../helpers/fake_export_repository.dart';
import '../helpers/fake_file_save_picker.dart';
import '../helpers/fake_module_state_repository.dart';
import '../helpers/fake_pin_repository.dart';

/// issue #17：设置页开启/关闭/修改 PIN；issue #18：备份导出与恢复；
/// issue #19：流水 CSV 导出；issue #45：设置页拆分与模块贡献条目。
void main() {
  late FakePinRepository fake;
  late FakeBackupRepository backupRepo;
  late FakeExportRepository exportRepo;
  late FakeFileSavePicker picker;
  late FakeModuleStateRepository moduleStateRepo;

  setUp(() {
    fake = FakePinRepository();
    backupRepo = FakeBackupRepository();
    exportRepo = FakeExportRepository();
    picker = FakeFileSavePicker();
    moduleStateRepo = FakeModuleStateRepository();
  });

  tearDown(() async {
    await moduleStateRepo.dispose();
  });

  Future<void> pumpSettings(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pinRepositoryProvider.overrideWithValue(fake),
          backupRepositoryProvider.overrideWithValue(backupRepo),
          exportRepositoryProvider.overrideWithValue(exportRepo),
          fileSavePickerProvider.overrideWithValue(picker),
          // 设置页会读「哪些模块启用」来决定显示哪些模块条目（#45）。
          moduleStateRepositoryProvider.overrideWithValue(moduleStateRepo),
        ],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  SwitchListTile pinSwitch(WidgetTester tester) =>
      tester.widget<SwitchListTile>(find.byKey(const Key('pin_switch')));

  testWidgets('未设 PIN：开关关闭、无「修改 PIN」入口、文案提示风险', (tester) async {
    await pumpSettings(tester);

    expect(pinSwitch(tester).value, isFalse);
    expect(find.textContaining('未开启'), findsOneWidget);
    expect(find.byKey(const Key('change_pin_tile')), findsNothing);
    expect(find.textContaining('不会加密数据库文件'), findsOneWidget);
  });

  testWidgets('开启 PIN：两次输入不一致时报错且不保存', (tester) async {
    await pumpSettings(tester);

    await tester.tap(find.byKey(const Key('pin_switch')));
    await tester.pumpAndSettle();
    expect(find.text('设置启动 PIN'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('pin_new_field')), '123456');
    await tester.enterText(
      find.byKey(const Key('pin_confirm_field')),
      '654321',
    );
    await tester.tap(find.byKey(const Key('pin_save_btn')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('pin_dialog_error')), findsOneWidget);
    expect(find.text('两次输入不一致'), findsOneWidget);
    expect(fake.setCalls, 0);
  });

  testWidgets('开启 PIN：输入一致后保存并刷新开关', (tester) async {
    await pumpSettings(tester);

    await tester.tap(find.byKey(const Key('pin_switch')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('pin_new_field')), '123456');
    await tester.enterText(
      find.byKey(const Key('pin_confirm_field')),
      '123456',
    );
    await tester.tap(find.byKey(const Key('pin_save_btn')));
    await tester.pumpAndSettle();

    expect(fake.setCalls, 1);
    expect(fake.pin, '123456');
    expect(pinSwitch(tester).value, isTrue);
    expect(find.byKey(const Key('change_pin_tile')), findsOneWidget);
    expect(find.text('已开启启动 PIN 锁'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5)); // 让 SnackBar 计时器收尾
  });

  testWidgets('关闭 PIN 需要先验证当前 PIN', (tester) async {
    fake = FakePinRepository(pin: '123456');
    await pumpSettings(tester);
    expect(pinSwitch(tester).value, isTrue);

    await tester.tap(find.byKey(const Key('pin_switch')));
    await tester.pumpAndSettle();
    expect(find.text('关闭 PIN 锁'), findsOneWidget);

    // 先输错：提示且不清除 PIN。
    await tester.enterText(
      find.byKey(const Key('pin_current_field')),
      '000000',
    );
    await tester.tap(find.byKey(const Key('pin_verify_btn')));
    await tester.pumpAndSettle();
    expect(find.text('PIN 不正确'), findsOneWidget);
    expect(fake.clearCalls, 0);

    // 再输对：清除 PIN，开关关闭。
    await tester.enterText(
      find.byKey(const Key('pin_current_field')),
      '123456',
    );
    await tester.tap(find.byKey(const Key('pin_verify_btn')));
    await tester.pumpAndSettle();

    expect(fake.clearCalls, 1);
    expect(fake.pin, isNull);
    expect(pinSwitch(tester).value, isFalse);
    expect(find.text('已关闭启动 PIN 锁'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('修改 PIN：验证旧 PIN 后覆盖为新 PIN', (tester) async {
    fake = FakePinRepository(pin: '123456');
    await pumpSettings(tester);

    await tester.tap(find.byKey(const Key('change_pin_tile')));
    await tester.pumpAndSettle();
    expect(find.text('验证当前 PIN'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('pin_current_field')),
      '123456',
    );
    await tester.tap(find.byKey(const Key('pin_verify_btn')));
    await tester.pumpAndSettle();
    expect(find.text('设置新 PIN'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('pin_new_field')), '654321');
    await tester.enterText(
      find.byKey(const Key('pin_confirm_field')),
      '654321',
    );
    await tester.tap(find.byKey(const Key('pin_save_btn')));
    await tester.pumpAndSettle();

    expect(fake.pin, '654321');
    expect(await fake.verifyPin('123456'), isFalse);
    expect(find.text('PIN 已更新'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('取消验证弹窗不会改动 PIN', (tester) async {
    fake = FakePinRepository(pin: '123456');
    await pumpSettings(tester);

    await tester.tap(find.byKey(const Key('change_pin_tile')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(fake.setCalls, 0);
    expect(fake.pin, '123456');
    expect(pinSwitch(tester).value, isTrue);
  });

  // ===== issue #18 备份与恢复 =====

  testWidgets('导出备份：把快照字节交给系统保存，成功提示带大小', (tester) async {
    await pumpSettings(tester);

    await tester.tap(find.byKey(const Key('backup_export_tile')));
    await tester.pumpAndSettle();

    expect(backupRepo.exportCalls, 1);
    expect(picker.saveCalls, 1);
    expect(picker.lastBytes, hasLength(4));
    // 建议文件名带时间戳，用户能按时间排序认出来。
    expect(picker.lastSuggestedName, startsWith('worthtrack-backup-'));
    expect(picker.lastSuggestedName, endsWith('.sqlite3'));
    expect(find.text('已导出备份（4 B）'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('导出时用户取消保存 → 不提示成功', (tester) async {
    picker.savePath = null;
    await pumpSettings(tester);

    await tester.tap(find.byKey(const Key('backup_export_tile')));
    await tester.pumpAndSettle();

    expect(backupRepo.exportCalls, 1);
    expect(find.textContaining('已导出备份'), findsNothing);
  });

  testWidgets('导出失败 → 提示重试，不崩', (tester) async {
    backupRepo.exportError = Exception('磁盘满');
    await pumpSettings(tester);

    await tester.tap(find.byKey(const Key('backup_export_tile')));
    await tester.pumpAndSettle();

    expect(find.text('导出失败，请重试'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('选了不合格的备份 → 说明原因，且绝不覆盖数据', (tester) async {
    backupRepo.inspection = const BackupInspection(
      path: '/tmp/other.sqlite3',
      sizeBytes: 1024,
      schemaVersion: 0,
      problem: BackupProblem.missingTables,
    );
    await pumpSettings(tester);

    await tester.tap(find.byKey(const Key('backup_restore_tile')));
    await tester.pumpAndSettle();

    expect(picker.openCalls, 1);
    expect(find.byKey(const Key('backup_problem_dialog')), findsOneWidget);
    expect(find.text(BackupProblem.missingTables.message), findsOneWidget);
    expect(find.byKey(const Key('backup_confirm_dialog')), findsNothing);
    expect(backupRepo.restoreCalls, 0);
  });

  testWidgets('恢复前的二次确认：取消则不动数据', (tester) async {
    await pumpSettings(tester);

    await tester.tap(find.byKey(const Key('backup_restore_tile')));
    await tester.pumpAndSettle();

    // 确认框要把「备份里有什么」摊开，用户才敢点覆盖。
    expect(find.byKey(const Key('backup_confirm_dialog')), findsOneWidget);
    expect(find.textContaining('2 个账户'), findsOneWidget);
    expect(find.textContaining('5 条流水'), findsOneWidget);

    await tester.tap(find.byKey(const Key('backup_cancel_btn')));
    await tester.pumpAndSettle();

    expect(backupRepo.restoreCalls, 0);
  });

  testWidgets('确认后执行恢复，提示恢复结果', (tester) async {
    await pumpSettings(tester);

    await tester.tap(find.byKey(const Key('backup_restore_tile')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('backup_confirm_btn')));
    await tester.pumpAndSettle();

    expect(backupRepo.restoreCalls, 1);
    expect(backupRepo.restoredPath, '/tmp/picked-backup.sqlite3');
    expect(find.text('已恢复备份：2 个账户、5 条流水'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('恢复失败 → 明确告知「数据没有被改动」', (tester) async {
    backupRepo.restoreError = Exception('boom');
    await pumpSettings(tester);

    await tester.tap(find.byKey(const Key('backup_restore_tile')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('backup_confirm_btn')));
    await tester.pumpAndSettle();

    expect(backupRepo.restoreCalls, 1);
    expect(find.text('恢复失败，当前数据没有被改动'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  // ===== issue #19 流水 CSV 导出 =====

  testWidgets('导出流水：交出去的是带 BOM 的 CSV，提示条数', (tester) async {
    await pumpSettings(tester);

    await tester.tap(find.byKey(const Key('csv_export_tile')));
    await tester.pumpAndSettle();

    expect(exportRepo.calls, 1);
    expect(picker.saveCalls, 1);
    expect(picker.lastSuggestedName, startsWith('worthtrack-transactions-'));
    expect(picker.lastSuggestedName, endsWith('.csv'));
    // BOM 必须在最前面，否则 Excel 打开中文乱码。
    expect(picker.lastBytes!.sublist(0, 3), csvUtf8Bom);
    expect(find.text('已导出 3 条流水（CSV）'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('导出流水时用户取消保存 → 不提示成功', (tester) async {
    picker.savePath = null;
    await pumpSettings(tester);

    await tester.tap(find.byKey(const Key('csv_export_tile')));
    await tester.pumpAndSettle();

    expect(exportRepo.calls, 1);
    expect(find.textContaining('已导出'), findsNothing);
  });

  testWidgets('导出流水失败 → 提示重试', (tester) async {
    exportRepo.error = Exception('查询失败');
    await pumpSettings(tester);

    await tester.tap(find.byKey(const Key('csv_export_tile')));
    await tester.pumpAndSettle();

    expect(find.text('导出失败，请重试'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });
}
