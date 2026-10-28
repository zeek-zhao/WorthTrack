import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worthtrack/app.dart';
import 'package:worthtrack/di.dart';

import 'helpers/fake_account_repository.dart';
import 'helpers/fake_net_worth_repository.dart';
import 'helpers/fake_pin_repository.dart';
import 'helpers/fake_position_repository.dart';
import 'helpers/fake_transaction_repository.dart';

void main() {
  late FakeAccountRepository accountRepo;
  late FakeCategoryRepository categoryRepo;
  late FakeTransactionRepository txnRepo;
  late FakeBudgetRepository budgetRepo;
  late FakeRecurringRepository recurringRepo;
  late FakePositionRepository positionRepo;
  late FakeNetWorthRepository netWorthRepo;
  late FakePinRepository pinRepo;

  setUp(() {
    accountRepo = FakeAccountRepository();
    categoryRepo = FakeCategoryRepository();
    txnRepo = FakeTransactionRepository();
    budgetRepo = FakeBudgetRepository();
    recurringRepo = FakeRecurringRepository();
    positionRepo = FakePositionRepository();
    netWorthRepo = FakeNetWorthRepository();
    pinRepo = FakePinRepository();
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

  Future<void> pumpApp(WidgetTester tester) async {
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
        ],
        child: const WorthTrackApp(),
      ),
    );
    accountRepo.emit([]);
    categoryRepo.emit([]);
    txnRepo.emit([]);
    await tester.pumpAndSettle();
  }

  testWidgets('应用启动进入底部导航（明细/报表/资产/投资/设置），真实 DI 被假仓储覆盖', (tester) async {
    await pumpApp(tester);

    // 底部导航五页签 + 明细页空态提示。
    expect(find.text('明细'), findsOneWidget);
    expect(find.text('报表'), findsOneWidget);
    expect(find.text('资产'), findsOneWidget);
    expect(find.text('投资'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('本月暂无交易，点 + 记一笔'), findsOneWidget);

    // 切到报表页。
    await tester.tap(find.text('报表'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('report_summary')), findsOneWidget);

    // 切到资产页。
    await tester.tap(find.text('资产'));
    await tester.pumpAndSettle();
    expect(find.text('净资产'), findsOneWidget);

    // 切到投资页。
    await tester.tap(find.text('投资'));
    await tester.pumpAndSettle();
    expect(find.text('投资持仓'), findsOneWidget);
    expect(find.text('暂无持仓，点 + 添加'), findsOneWidget);

    // 切到设置页。
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(find.text('启动 PIN 锁'), findsOneWidget);
    expect(find.text('备份与恢复'), findsOneWidget);
    expect(find.text('导出备份'), findsOneWidget);
    expect(find.text('数据导出'), findsOneWidget);
    expect(find.text('导出流水（CSV）'), findsOneWidget);
  });

  testWidgets('已设 PIN 时启动先出锁屏，解锁后才进入首页', (tester) async {
    pinRepo = FakePinRepository(pin: '123456');
    await pumpApp(tester);

    expect(find.byKey(const Key('lock_pin_field')), findsOneWidget);
    expect(find.text('明细'), findsNothing);

    await tester.enterText(find.byKey(const Key('lock_pin_field')), '123456');
    await tester.pumpAndSettle();

    expect(find.text('明细'), findsOneWidget);
    expect(find.byKey(const Key('lock_pin_field')), findsNothing);
  });

  testWidgets('从后台返回会重新上锁', (tester) async {
    pinRepo = FakePinRepository(pin: '123456');
    await pumpApp(tester);
    await tester.enterText(find.byKey(const Key('lock_pin_field')), '123456');
    await tester.pumpAndSettle();
    expect(find.text('明细'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('lock_pin_field')), findsOneWidget);
  });
}
