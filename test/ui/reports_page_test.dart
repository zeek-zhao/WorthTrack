import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worthtrack/data/db/app_database.dart';
import 'package:worthtrack/di.dart';
import 'package:worthtrack/ui/reports/reports_page.dart';

import '../helpers/fake_transaction_repository.dart';

/// issue #9/#10 验收：报表页 Widget 测试（汇总卡、预算超支横幅、月/年切换、周期入口）。
/// 与项目其他 UI 测试一致，使用假仓储（真 Drift 在 fake-async 测试中会遗留 Timer）。
void main() {
  late FakeCategoryRepository categoryRepo;
  late FakeTransactionRepository txnRepo;
  late FakeBudgetRepository budgetRepo;
  late FakeRecurringRepository recurringRepo;

  setUp(() {
    categoryRepo = FakeCategoryRepository();
    txnRepo = FakeTransactionRepository();
    budgetRepo = FakeBudgetRepository();
    recurringRepo = FakeRecurringRepository();
  });

  tearDown(() {
    categoryRepo.dispose();
    txnRepo.dispose();
    budgetRepo.dispose();
    recurringRepo.dispose();
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          categoryRepositoryProvider.overrideWithValue(categoryRepo),
          transactionRepositoryProvider.overrideWithValue(txnRepo),
          budgetRepositoryProvider.overrideWithValue(budgetRepo),
          recurringRepositoryProvider.overrideWithValue(recurringRepo),
        ],
        child: MaterialApp(
          home: ReportsPage(initialMonth: DateTime(2026, 10, 15)),
        ),
      ),
    );
    // 先 pump 建立订阅，再推数据。
    categoryRepo.emit([
      makeTestCategory(10, '餐饮', CategoryKind.expense, icon: '🍜'),
      makeTestCategory(11, '购物', CategoryKind.expense, icon: '🛒'),
    ]);
    txnRepo.emit([]);
    budgetRepo.emit([]);
    recurringRepo.emit([]);
    await tester.pumpAndSettle();
  }

  testWidgets('汇总卡展示当月收入/支出/结余', (tester) async {
    await pump(tester);
    txnRepo.emit([
      makeTestTransaction(
        1,
        type: TxnType.expense,
        accountId: 1,
        categoryId: 10,
        amountMinor: 2580,
        occurredAt: DateTime(2026, 10, 5, 12),
      ),
      makeTestTransaction(
        2,
        type: TxnType.income,
        accountId: 1,
        amountMinor: 10000,
        occurredAt: DateTime(2026, 10, 1, 12),
      ),
    ]);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('report_summary')), findsOneWidget);
    expect(find.text('¥25.80'), findsOneWidget); // 支出
    expect(find.text('¥100.00'), findsOneWidget); // 收入
    expect(find.text('¥74.20'), findsOneWidget); // 结余
  });

  testWidgets('超支时显示红色横幅并点名超支分类', (tester) async {
    await pump(tester);
    budgetRepo.emit([
      makeTestBudgetStatus(
        categoryId: 10,
        categoryName: '餐饮',
        amountMinor: 1000,
        spentMinor: 1500,
      ),
    ]);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('budget_overspend_banner')), findsOneWidget);
    expect(find.textContaining('超支'), findsWidgets);
    expect(find.textContaining('餐饮'), findsWidgets);
  });

  testWidgets('未超支时不显示超支横幅', (tester) async {
    await pump(tester);
    budgetRepo.emit([
      makeTestBudgetStatus(
        categoryId: 10,
        categoryName: '餐饮',
        amountMinor: 1000,
        spentMinor: 500,
      ),
    ]);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('budget_overspend_banner')), findsNothing);
    expect(find.textContaining('已用 ¥5.00'), findsOneWidget);
  });

  testWidgets('切换年模式：标题变为年份并汇总全年', (tester) async {
    await pump(tester);
    txnRepo.emit([
      makeTestTransaction(
        1,
        type: TxnType.expense,
        accountId: 1,
        amountMinor: 6600,
        occurredAt: DateTime(2026, 3, 15, 12),
      ),
    ]);
    await tester.pumpAndSettle();

    await tester.tap(find.text('年'));
    await tester.pumpAndSettle();

    expect(find.text('2026年'), findsOneWidget);
    expect(find.byKey(const Key('report_summary')), findsOneWidget);
    expect(find.text('¥66.00'), findsOneWidget); // 全年支出
  });

  testWidgets('周期账单入口可进入规则页', (tester) async {
    await pump(tester);
    // 入口卡片在列表底部，滚动到可见。
    for (var i = 0; i < 6; i++) {
      if (find.byKey(const Key('recurring_entry')).evaluate().isNotEmpty) {
        break;
      }
      await tester.drag(
        find.byKey(const Key('report_list')),
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(const Key('recurring_entry')));
    await tester.pumpAndSettle();
    expect(find.text('暂无周期账单，点 + 新建规则'), findsOneWidget);
  });
}
