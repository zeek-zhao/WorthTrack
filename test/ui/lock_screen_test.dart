import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worthtrack/di.dart';
import 'package:worthtrack/ui/lock/lock_screen.dart';

import '../helpers/fake_pin_repository.dart';

/// issue #17 验收：锁屏解锁流程 Widget 测试。
void main() {
  late FakePinRepository fake;

  setUp(() {
    fake = FakePinRepository(pin: '123456');
  });

  /// 把锁屏挂在一个可切换的宿主里，解锁后宿主换成「主界面」占位。
  Future<void> pumpLock(WidgetTester tester) async {
    var unlocked = false;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [pinRepositoryProvider.overrideWithValue(fake)],
        child: MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) => unlocked
                ? const Scaffold(body: Center(child: Text('已进入主界面')))
                : LockScreen(onUnlocked: () => setState(() => unlocked = true)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('正确 PIN 解锁进入主界面', (tester) async {
    await pumpLock(tester);
    expect(find.text('输入 PIN'), findsOneWidget);
    expect(find.text('已进入主界面'), findsNothing);

    await tester.enterText(find.byKey(const Key('lock_pin_field')), '123456');
    await tester.pumpAndSettle();

    expect(fake.verifyCalls, 1);
    expect(find.text('已进入主界面'), findsOneWidget);
  });

  testWidgets('错误 PIN 提示并清空输入，可再试', (tester) async {
    await pumpLock(tester);

    await tester.enterText(find.byKey(const Key('lock_pin_field')), '000000');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('lock_error')), findsOneWidget);
    expect(find.text('PIN 不正确，请重试'), findsOneWidget);
    expect(find.text('已进入主界面'), findsNothing);
    final field = tester.widget<TextField>(
      find.byKey(const Key('lock_pin_field')),
    );
    expect(field.controller!.text, isEmpty);

    // 再输对即可进入。
    await tester.enterText(find.byKey(const Key('lock_pin_field')), '123456');
    await tester.pumpAndSettle();
    expect(find.text('已进入主界面'), findsOneWidget);
  });

  testWidgets('未输满 6 位不触发校验', (tester) async {
    await pumpLock(tester);

    await tester.enterText(find.byKey(const Key('lock_pin_field')), '123');
    await tester.pumpAndSettle();

    expect(fake.verifyCalls, 0);
    expect(find.byKey(const Key('lock_error')), findsNothing);
  });

  testWidgets('重新输入时清掉上一次的错误提示', (tester) async {
    await pumpLock(tester);
    await tester.enterText(find.byKey(const Key('lock_pin_field')), '000000');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('lock_error')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('lock_pin_field')), '1');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('lock_error')), findsNothing);
  });

  testWidgets('忘记 PIN → 确认重置 → 清除 PIN 并进入（数据不丢由仓储层保证）', (tester) async {
    await pumpLock(tester);

    await tester.tap(find.byKey(const Key('lock_forgot_btn')));
    await tester.pumpAndSettle();
    expect(find.text('重置 PIN 锁？'), findsOneWidget);
    expect(find.textContaining('数据都不会被删除'), findsOneWidget);

    await tester.tap(find.byKey(const Key('lock_reset_confirm')));
    await tester.pumpAndSettle();

    expect(fake.clearCalls, 1);
    expect(fake.pin, isNull);
    expect(find.text('已进入主界面'), findsOneWidget);
  });

  testWidgets('忘记 PIN 弹窗点取消则留在锁屏', (tester) async {
    await pumpLock(tester);

    await tester.tap(find.byKey(const Key('lock_forgot_btn')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(fake.clearCalls, 0);
    expect(find.text('输入 PIN'), findsOneWidget);
    expect(find.text('已进入主界面'), findsNothing);
  });
}
