import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worthtrack/data/db/app_database.dart';
import 'package:worthtrack/di.dart';
import 'package:worthtrack/ui/accounts/accounts_page.dart';

import '../helpers/fake_account_repository.dart';

/// issue #5 验收：建账户 Widget 测试。
void main() {
  late FakeAccountRepository fake;

  setUp(() {
    fake = FakeAccountRepository();
  });

  tearDown(() {
    fake.dispose();
  });

  Future<void> pumpPage(WidgetTester tester, [List<Account>? initial]) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [accountRepositoryProvider.overrideWithValue(fake)],
        child: const MaterialApp(home: AccountsPage()),
      ),
    );
    // 先 pump 建立订阅，再推送数据（广播流不缓存历史事件）。
    fake.emit(initial ?? []);
    await tester.pumpAndSettle();
  }

  testWidgets('空列表展示总资产 0.00 并提供新建入口', (tester) async {
    await pumpPage(tester);

    expect(find.text('总资产'), findsOneWidget);
    expect(find.text('¥0.00'), findsOneWidget);
    expect(find.byKey(const Key('add_account_fab')), findsOneWidget);
  });

  testWidgets('建账户：填名/选类型/填初始余额后出现在列表且总资产更新', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.byKey(const Key('add_account_fab')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('account_name_field')), '微信零钱');
    await tester.tap(find.byKey(const Key('type_储蓄卡')));
    await tester.enterText(
      find.byKey(const Key('account_balance_field')),
      '1234.56',
    );
    await tester.tap(find.byKey(const Key('account_save_btn')));
    await tester.pumpAndSettle();

    // 列表出现新账户，余额正确展示（列表行 + 总资产卡片各一处）。
    expect(find.text('微信零钱'), findsOneWidget);
    expect(find.text('¥1234.56'), findsNWidgets(2));
  });

  testWidgets('账户名为空时提示且不提交', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.byKey(const Key('add_account_fab')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('account_save_btn')));
    await tester.pumpAndSettle();

    expect(find.text('请输入账户名'), findsOneWidget);
    // 对话框未关闭。
    expect(find.text('新建账户'), findsOneWidget);
  });

  testWidgets('非法金额格式提示且不提交', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.byKey(const Key('add_account_fab')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('account_name_field')), '测试账户');
    await tester.enterText(
      find.byKey(const Key('account_balance_field')),
      '12.345',
    );
    await tester.tap(find.byKey(const Key('account_save_btn')));
    await tester.pumpAndSettle();

    expect(find.text('金额格式：最多两位小数，如 123.45'), findsOneWidget);
    expect(find.text('新建账户'), findsOneWidget);
  });

  testWidgets('已有账户正常展示名称与余额', (tester) async {
    await pumpPage(tester, [
      makeTestAccount(1, '零钱包', AccountType.cash, 10000),
      makeTestAccount(2, '花呗', AccountType.credit, -5000),
    ]);

    expect(find.text('零钱包'), findsOneWidget);
    expect(find.text('现金'), findsOneWidget); // 类型标签
    expect(find.text('¥100.00'), findsOneWidget);
    expect(find.text('花呗'), findsOneWidget);
    expect(find.text('¥-50.00'), findsOneWidget);
  });
}
