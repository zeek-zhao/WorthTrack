import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worthtrack/di.dart';
import 'package:worthtrack/ui/settings/settings_page.dart';

import '../helpers/fake_pin_repository.dart';

/// issue #17：设置页开启/关闭/修改 PIN。
void main() {
  late FakePinRepository fake;

  setUp(() {
    fake = FakePinRepository();
  });

  Future<void> pumpSettings(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [pinRepositoryProvider.overrideWithValue(fake)],
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
}
