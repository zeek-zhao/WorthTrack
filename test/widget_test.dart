import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worthtrack/app.dart';
import 'package:worthtrack/core/module/module_providers.dart';
import 'package:worthtrack/di.dart';

import 'helpers/fake_account_repository.dart';
import 'helpers/fake_backup_repository.dart';
import 'helpers/fake_export_repository.dart';
import 'helpers/fake_file_save_picker.dart';
import 'helpers/fake_module_state_repository.dart';
import 'helpers/fake_net_worth_repository.dart';
import 'helpers/fake_pin_repository.dart';
import 'helpers/fake_position_repository.dart';
import 'helpers/fake_transaction_repository.dart';

/// 应用级冒烟测试：真实 `WorthTrackApp` + 真实 go_router，只把仓储换成假实现。
///
/// issue #44 之后应用首页是 launcher，finance 是**一个模块**，
/// 它内部的四个 tab 不再是应用级底部导航。
void main() {
  late FakeAccountRepository accountRepo;
  late FakeCategoryRepository categoryRepo;
  late FakeTransactionRepository txnRepo;
  late FakeBudgetRepository budgetRepo;
  late FakeRecurringRepository recurringRepo;
  late FakePositionRepository positionRepo;
  late FakeNetWorthRepository netWorthRepo;
  late FakePinRepository pinRepo;
  late FakeBackupRepository backupRepo;
  late FakeExportRepository exportRepo;
  late FakeFileSavePicker picker;
  late FakeModuleStateRepository moduleStateRepo;

  setUp(() {
    accountRepo = FakeAccountRepository();
    categoryRepo = FakeCategoryRepository();
    txnRepo = FakeTransactionRepository();
    budgetRepo = FakeBudgetRepository();
    recurringRepo = FakeRecurringRepository();
    positionRepo = FakePositionRepository();
    netWorthRepo = FakeNetWorthRepository();
    pinRepo = FakePinRepository();
    backupRepo = FakeBackupRepository();
    exportRepo = FakeExportRepository();
    picker = FakeFileSavePicker();
    moduleStateRepo = FakeModuleStateRepository();
  });

  tearDown(() {
    accountRepo.dispose();
    categoryRepo.dispose();
    txnRepo.dispose();
    budgetRepo.dispose();
    recurringRepo.dispose();
    positionRepo.dispose();
    netWorthRepo.dispose();
  });

  Future<void> pumpApp(
    WidgetTester tester, {
    String initialLocation = '/',
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountRepositoryProvider.overrideWithValue(accountRepo),
          categoryRepositoryProvider.overrideWithValue(categoryRepo),
          transactionRepositoryProvider.overrideWithValue(txnRepo),
          budgetRepositoryProvider.overrideWithValue(budgetRepo),
          recurringRepositoryProvider.overrideWithValue(recurringRepo),
          positionRepositoryProvider.overrideWithValue(positionRepo),
          netWorthRepositoryProvider.overrideWithValue(netWorthRepo),
          pinRepositoryProvider.overrideWithValue(pinRepo),
          backupRepositoryProvider.overrideWithValue(backupRepo),
          exportRepositoryProvider.overrideWithValue(exportRepo),
          fileSavePickerProvider.overrideWithValue(picker),
          moduleStateRepositoryProvider.overrideWithValue(moduleStateRepo),
        ],
        child: WorthTrackApp(initialLocation: initialLocation),
      ),
    );
    accountRepo.emit([]);
    categoryRepo.emit([]);
    txnRepo.emit([]);
    await tester.pumpAndSettle();
  }

  testWidgets('启动进入 launcher：模块卡片 + 快捷动作 + 设置入口', (tester) async {
    await pumpApp(tester);

    expect(find.text('WorthTrack'), findsOneWidget);
    expect(find.byKey(const Key('launcher-module-finance')), findsOneWidget);
    expect(find.text('记账与资产'), findsOneWidget);
    expect(find.text('记一笔'), findsOneWidget);
    expect(find.byKey(const Key('launcher-settings')), findsOneWidget);

    // 应用级底部导航已经是过去式。
    expect(find.text('设置'), findsNothing);
  });

  testWidgets('点模块卡片进入 finance，四个内部 tab 都在且能切换', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byKey(const Key('launcher-module-finance')));
    await tester.pumpAndSettle();

    expect(find.text('明细'), findsOneWidget);
    expect(find.text('报表'), findsOneWidget);
    expect(find.text('资产'), findsOneWidget);
    expect(find.text('投资'), findsOneWidget);
    expect(find.text('本月暂无交易，点 + 记一笔'), findsOneWidget);

    await tester.tap(find.text('报表'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('report_summary')), findsOneWidget);

    await tester.tap(find.text('资产'));
    await tester.pumpAndSettle();
    expect(find.text('净资产'), findsOneWidget);

    await tester.tap(find.text('投资'));
    await tester.pumpAndSettle();
    expect(find.text('投资持仓'), findsOneWidget);
    expect(find.text('暂无持仓，点 + 添加'), findsOneWidget);
  });

  testWidgets('模块内左下角出口能回到 launcher（桌面端没有系统返回键）', (tester) async {
    await pumpApp(tester, initialLocation: '/finance');

    expect(find.text('明细'), findsOneWidget);

    await tester.tap(find.byKey(const Key('finance-home')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('launcher-module-finance')), findsOneWidget);
    expect(find.text('明细'), findsNothing);
  });

  testWidgets('从 launcher 能进设置页：PIN / 备份 / CSV 导出都在', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byKey(const Key('launcher-settings')));
    await tester.pumpAndSettle();

    expect(find.text('启动 PIN 锁'), findsOneWidget);
    expect(find.text('备份与恢复'), findsOneWidget);
    expect(find.text('导出备份'), findsOneWidget);
    expect(find.text('数据导出'), findsOneWidget);
    expect(find.text('导出流水（CSV）'), findsOneWidget);
  });

  testWidgets('已设 PIN 时启动先出锁屏，解锁后才进 launcher', (tester) async {
    pinRepo = FakePinRepository(pin: '123456');
    await pumpApp(tester);

    expect(find.byKey(const Key('lock_pin_field')), findsOneWidget);
    expect(find.byKey(const Key('launcher-module-finance')), findsNothing);

    await tester.enterText(find.byKey(const Key('lock_pin_field')), '123456');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('launcher-module-finance')), findsOneWidget);
    expect(find.byKey(const Key('lock_pin_field')), findsNothing);
  });

  testWidgets('从后台返回会重新上锁', (tester) async {
    pinRepo = FakePinRepository(pin: '123456');
    await pumpApp(tester);
    await tester.enterText(find.byKey(const Key('lock_pin_field')), '123456');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('launcher-module-finance')), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('lock_pin_field')), findsOneWidget);
  });
}
