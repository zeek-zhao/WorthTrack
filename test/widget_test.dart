import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worthtrack/app.dart';
import 'package:worthtrack/di.dart';

import 'helpers/fake_account_repository.dart';
import 'helpers/fake_position_repository.dart';
import 'helpers/fake_transaction_repository.dart';

void main() {
  late FakeAccountRepository accountRepo;
  late FakeCategoryRepository categoryRepo;
  late FakeTransactionRepository txnRepo;
  late FakeBudgetRepository budgetRepo;
  late FakeRecurringRepository recurringRepo;
  late FakePositionRepository positionRepo;

  setUp(() {
    accountRepo = FakeAccountRepository();
    categoryRepo = FakeCategoryRepository();
    txnRepo = FakeTransactionRepository();
    budgetRepo = FakeBudgetRepository();
    recurringRepo = FakeRecurringRepository();
    positionRepo = FakePositionRepository();
  });

  tearDown(() {
    accountRepo.dispose();
    categoryRepo.dispose();
    txnRepo.dispose();
    budgetRepo.dispose();
    recurringRepo.dispose();
    positionRepo.dispose();
  });

  testWidgets('应用启动进入底部导航（明细/报表/资产/投资），真实 DI 被假仓储覆盖', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountRepositoryProvider.overrideWithValue(accountRepo),
          categoryRepositoryProvider.overrideWithValue(categoryRepo),
          transactionRepositoryProvider.overrideWithValue(txnRepo),
          budgetRepositoryProvider.overrideWithValue(budgetRepo),
          recurringRepositoryProvider.overrideWithValue(recurringRepo),
          positionRepositoryProvider.overrideWithValue(positionRepo),
        ],
        child: const WorthTrackApp(),
      ),
    );
    accountRepo.emit([]);
    categoryRepo.emit([]);
    txnRepo.emit([]);
    await tester.pumpAndSettle();

    // 底部导航四页签 + 明细页空态提示。
    expect(find.text('明细'), findsOneWidget);
    expect(find.text('报表'), findsOneWidget);
    expect(find.text('资产'), findsOneWidget);
    expect(find.text('投资'), findsOneWidget);
    expect(find.text('本月暂无交易，点 + 记一笔'), findsOneWidget);

    // 切到报表页。
    await tester.tap(find.text('报表'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('report_summary')), findsOneWidget);

    // 切到资产页。
    await tester.tap(find.text('资产'));
    await tester.pumpAndSettle();
    expect(find.text('总资产'), findsOneWidget);

    // 切到投资页。
    await tester.tap(find.text('投资'));
    await tester.pumpAndSettle();
    expect(find.text('投资持仓'), findsOneWidget);
    expect(find.text('暂无持仓，点 + 添加'), findsOneWidget);
  });
}
