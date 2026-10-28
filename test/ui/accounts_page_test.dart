import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worthtrack/data/db/app_database.dart';
import 'package:worthtrack/di.dart';
import 'package:worthtrack/domain/net_worth.dart';
import 'package:worthtrack/ui/accounts/accounts_page.dart';

import '../helpers/fake_account_repository.dart';
import '../helpers/fake_net_worth_repository.dart';

/// issue #5 验收：建账户 Widget 测试。
/// issue #16 验收：资产总览（现金/投资拆分）与净资产曲线渲染。
void main() {
  late FakeAccountRepository fake;
  late FakeNetWorthRepository netWorthFake;

  setUp(() {
    fake = FakeAccountRepository();
    netWorthFake = FakeNetWorthRepository();
  });

  tearDown(() {
    fake.dispose();
    netWorthFake.dispose();
  });

  /// 按当前账户余额推算总览（模拟仓储对账户变更的响应）。
  AssetOverview deriveOverview() =>
      makeTestOverview(cashMinor: cashLikeBalanceMinor(fake.current));

  Future<void> pumpPage(
    WidgetTester tester, {
    List<Account>? accounts,
    AssetOverview? overview,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountRepositoryProvider.overrideWithValue(fake),
          netWorthRepositoryProvider.overrideWithValue(netWorthFake),
        ],
        child: const MaterialApp(home: AccountsPage()),
      ),
    );
    // 先 pump 建立订阅，再推送数据（广播流不缓存历史事件）。
    fake.emit(accounts ?? []);
    netWorthFake.emit(overview ?? deriveOverview());
    await tester.pumpAndSettle();
  }

  testWidgets('空账本：净资产 0.00、曲线空态、提供新建入口', (tester) async {
    await pumpPage(tester);

    expect(find.text('净资产'), findsOneWidget);
    expect(find.byKey(const Key('net_worth_value')), findsOneWidget);
    expect(find.text('¥0.00'), findsNWidgets(3)); // 净资产 + 现金类 + 投资市值
    expect(find.byKey(const Key('net_worth_chart_empty')), findsOneWidget);
    expect(find.byKey(const Key('add_account_fab')), findsOneWidget);
  });

  testWidgets('建账户：填名/选类型/填初始余额后出现在列表且净资产更新', (tester) async {
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

    // 账户变更后总览随之更新（生产由三条流组合自动触发）。
    netWorthFake.emit(deriveOverview());
    await tester.pumpAndSettle();

    // 列表行 + 净资产 + 现金类各一处。
    expect(find.text('微信零钱'), findsOneWidget);
    expect(find.text('¥1234.56'), findsNWidgets(3));
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

  testWidgets('已有账户正常展示名称与余额，信用卡负余额抵减净资产', (tester) async {
    await pumpPage(
      tester,
      accounts: [
        makeTestAccount(1, '零钱包', AccountType.cash, 10000),
        makeTestAccount(2, '花呗', AccountType.credit, -5000),
      ],
    );

    expect(find.text('零钱包'), findsOneWidget);
    expect(find.text('现金'), findsOneWidget); // 类型标签
    expect(find.text('¥100.00'), findsOneWidget); // 列表行
    expect(find.text('花呗'), findsOneWidget);
    expect(find.text('¥-50.00'), findsOneWidget);
    // 净资产 = 100 - 50 = 50，现金类同样 50。
    expect(find.text('¥50.00'), findsNWidgets(2));
  });

  testWidgets('投资市值计入净资产，未录价持仓给出提示', (tester) async {
    await pumpPage(
      tester,
      accounts: [makeTestAccount(1, '工资卡', AccountType.bank, 100000)],
      overview: makeTestOverview(
        cashMinor: 100000,
        investmentMinor: 25500000,
        unpricedPositionCount: 2,
      ),
    );

    expect(find.text('¥256000.00'), findsOneWidget); // 1000 + 255000
    expect(find.text('¥255000.00'), findsOneWidget); // 投资市值
    expect(find.byKey(const Key('unpriced_hint')), findsOneWidget);
    expect(find.text('2 只持仓未录价，市值未计入净资产'), findsOneWidget);
    expect(find.byKey(const Key('investment_account_hint')), findsNothing);
  });

  testWidgets('投资账户余额不计入净资产，但单独提示', (tester) async {
    await pumpPage(
      tester,
      accounts: [makeTestAccount(1, '券商', AccountType.investment, 300000)],
      overview: makeTestOverview(
        cashMinor: 0,
        investmentMinor: 25500000,
        investmentAccountBalanceMinor: 300000,
      ),
    );

    // 净资产只含持仓市值，券商余额 3000 元不参与。
    expect(find.text('¥255000.00'), findsNWidgets(2)); // 净资产 + 投资市值
    expect(find.byKey(const Key('investment_account_hint')), findsOneWidget);
    expect(find.text('投资账户余额 ¥3000.00 未计入（避免与持仓市值重复）'), findsOneWidget);
  });

  testWidgets('净资产曲线：多点时渲染折线、月份标签与环比', (tester) async {
    await pumpPage(
      tester,
      accounts: [makeTestAccount(1, '工资卡', AccountType.bank, 105000)],
      overview: makeTestOverview(
        cashMinor: 105000,
        series: makeTestSeries([100000, 102000, 105000]),
      ),
    );

    expect(find.byKey(const Key('net_worth_chart')), findsOneWidget);
    expect(find.byKey(const Key('net_worth_chart_empty')), findsNothing);
    expect(find.text('近 3 个月'), findsOneWidget);
    expect(find.text('8月'), findsOneWidget);
    expect(find.text('9月'), findsOneWidget);
    expect(find.text('10月'), findsOneWidget);
    expect(find.text('较上月 +¥30.00（+2.94%）'), findsOneWidget);
  });

  testWidgets('净资产曲线：只有 1 个点时显示空态而不是折线', (tester) async {
    await pumpPage(
      tester,
      overview: makeTestOverview(
        cashMinor: 10000,
        series: makeTestSeries([10000]),
      ),
    );

    expect(find.byKey(const Key('net_worth_chart')), findsNothing);
    expect(find.byKey(const Key('net_worth_chart_empty')), findsOneWidget);
  });
}
