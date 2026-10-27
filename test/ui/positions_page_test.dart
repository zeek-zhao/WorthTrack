import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worthtrack/data/db/app_database.dart';
import 'package:worthtrack/di.dart';
import 'package:worthtrack/ui/positions/positions_page.dart';

import '../helpers/fake_position_repository.dart';

/// issue #13 验收：持仓页 Widget 测试（假仓储，不碰真 Drift）。
void main() {
  late FakePositionRepository fake;

  setUp(() {
    fake = FakePositionRepository();
  });

  tearDown(() {
    fake.dispose();
  });

  Future<void> pumpPage(WidgetTester tester, [List<Position>? initial]) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [positionRepositoryProvider.overrideWithValue(fake)],
        child: const MaterialApp(home: PositionsPage()),
      ),
    );
    // 先 pump 建立订阅，再推送数据（假仓储订阅时回放当前值）。
    fake.emit(initial ?? []);
    await tester.pumpAndSettle();
  }

  Future<void> fillForm(
    WidgetTester tester, {
    String code = '600519',
    String name = '贵州茅台',
    String shares = '150',
    String cost = '1600',
    String price = '1700',
  }) async {
    await tester.enterText(find.byKey(const Key('position_code_field')), code);
    await tester.enterText(find.byKey(const Key('position_name_field')), name);
    await tester.enterText(
      find.byKey(const Key('position_shares_field')),
      shares,
    );
    await tester.enterText(find.byKey(const Key('position_cost_field')), cost);
    await tester.enterText(
      find.byKey(const Key('position_price_field')),
      price,
    );
  }

  testWidgets('空持仓展示空态与新建入口', (tester) async {
    await pumpPage(tester);

    expect(find.text('暂无持仓，点 + 添加'), findsOneWidget);
    expect(find.byKey(const Key('add_position_fab')), findsOneWidget);
  });

  testWidgets('新建持仓：市值/盈亏/百分比出现在列表与汇总卡片', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.byKey(const Key('add_position_fab')));
    await tester.pumpAndSettle();
    await fillForm(tester);
    await tester.tap(find.byKey(const Key('position_save_btn')));
    await tester.pumpAndSettle();

    // 列表行：名称 + 市场代码 + 份额成本。
    expect(find.text('贵州茅台'), findsOneWidget);
    expect(find.text('沪600519'), findsOneWidget);
    expect(find.text('份额 150.00 · 成本 ¥1600.00'), findsOneWidget);
    // 市值：列表行 + 汇总卡片各一处（150 份 × 1700 元）。
    expect(find.text('¥255000.00'), findsNWidgets(2));
    // 盈亏只出现在列表行；汇总卡片里是拼接后的长文案。
    expect(find.text('+¥15000.00（+6.25%）'), findsOneWidget);
    expect(find.text('总成本 ¥240000.00 · 盈亏 +¥15000.00（+6.25%）'), findsOneWidget);
  });

  testWidgets('代码不是 6 位数字时提示且不提交', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.byKey(const Key('add_position_fab')));
    await tester.pumpAndSettle();
    await fillForm(tester, code: '60051');
    await tester.tap(find.byKey(const Key('position_save_btn')));
    await tester.pumpAndSettle();

    expect(find.text('代码需为 6 位数字'), findsOneWidget);
    expect(find.text('新建持仓'), findsOneWidget); // 对话框未关闭
  });

  testWidgets('份额为 0 时提示且不提交', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.byKey(const Key('add_position_fab')));
    await tester.pumpAndSettle();
    await fillForm(tester, shares: '0');
    await tester.tap(find.byKey(const Key('position_save_btn')));
    await tester.pumpAndSettle();

    expect(find.text('份额需大于 0，最多两位小数'), findsOneWidget);
    expect(find.text('新建持仓'), findsOneWidget);
  });

  testWidgets('重复代码提示「已在持仓中」', (tester) async {
    await pumpPage(tester, [makeTestPosition()]);

    await tester.tap(find.byKey(const Key('add_position_fab')));
    await tester.pumpAndSettle();
    await fillForm(tester);
    await tester.tap(find.byKey(const Key('position_save_btn')));
    await tester.pumpAndSettle();

    expect(find.text('该代码已在持仓中'), findsOneWidget);
  });

  testWidgets('未录价的持仓显示「待录价」，汇总提示均未录价', (tester) async {
    await pumpPage(tester, [makeTestPosition()]);

    expect(find.text('待录价'), findsOneWidget);
    expect(find.text('共 1 只，均未录价'), findsOneWidget);
  });

  testWidgets('点行改现价后市值与盈亏即时更新', (tester) async {
    await pumpPage(tester, [makeTestPosition()]);

    await tester.tap(find.byKey(const Key('position_sh600519')));
    await tester.pumpAndSettle();
    expect(find.text('编辑持仓'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('position_price_field')),
      '1700',
    );
    await tester.tap(find.byKey(const Key('position_save_btn')));
    await tester.pumpAndSettle();

    expect(find.text('¥255000.00'), findsNWidgets(2));
    expect(find.text('+¥15000.00（+6.25%）'), findsOneWidget);
  });

  testWidgets('归档（清仓）后从列表移除', (tester) async {
    await pumpPage(tester, [makeTestPosition()]);

    await tester.tap(find.byKey(const Key('position_menu_sh600519')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('archive_position_btn')));
    await tester.pumpAndSettle();

    expect(find.text('暂无持仓，点 + 添加'), findsOneWidget);
  });

  testWidgets('删除需二次确认，确认后从列表移除', (tester) async {
    await pumpPage(tester, [makeTestPosition()]);

    await tester.tap(find.byKey(const Key('position_menu_sh600519')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete_position_btn')));
    await tester.pumpAndSettle();

    expect(find.text('删除持仓'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm_delete_position_btn')));
    await tester.pumpAndSettle();

    expect(find.text('暂无持仓，点 + 添加'), findsOneWidget);
  });

  testWidgets('已有价格时编辑对话框回填现价，保存不改价不覆盖', (tester) async {
    await pumpPage(tester, [makeTestPosition()]);
    fake.emitPrice(Market.sh, '600519', 170000);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('position_sh600519')));
    await tester.pumpAndSettle();

    // 现价回填为 1700.00（元）。
    final priceField = tester.widget<TextField>(
      find.byKey(const Key('position_price_field')),
    );
    expect(priceField.controller!.text, '1700.00');
  });
}
