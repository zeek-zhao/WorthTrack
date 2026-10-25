import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worthtrack/data/db/app_database.dart';
import 'package:worthtrack/data/dao/transaction_dao.dart';
import 'package:worthtrack/di.dart';
import 'package:worthtrack/ui/transactions/transactions_page.dart';

import '../helpers/fake_account_repository.dart';
import '../helpers/fake_transaction_repository.dart';

/// issue #6 验收：交易录入 Widget 测试。
void main() {
  late FakeAccountRepository accountRepo;
  late FakeCategoryRepository categoryRepo;
  late FakeTransactionRepository txnRepo;

  setUp(() {
    accountRepo = FakeAccountRepository();
    categoryRepo = FakeCategoryRepository();
    txnRepo = FakeTransactionRepository();
  });

  tearDown(() {
    accountRepo.dispose();
    categoryRepo.dispose();
    txnRepo.dispose();
  });

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountRepositoryProvider.overrideWithValue(accountRepo),
          categoryRepositoryProvider.overrideWithValue(categoryRepo),
          transactionRepositoryProvider.overrideWithValue(txnRepo),
        ],
        child: const MaterialApp(home: TransactionsPage()),
      ),
    );
    // 先 pump 建立订阅，再推数据。
    accountRepo.emit([makeTestAccount(1, '微信零钱', AccountType.cash, 10000)]);
    categoryRepo.emit([
      makeTestCategory(10, '餐饮', CategoryKind.expense, icon: '🍜'),
      makeTestCategory(11, '购物', CategoryKind.expense, icon: '🛒'),
      makeTestCategory(20, '工资', CategoryKind.income, icon: '💼'),
    ]);
    txnRepo.emit([]);
    await tester.pumpAndSettle();
  }

  testWidgets('录入支出：金额/账户/分类提交后写入仓储', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.byKey(const Key('add_txn_fab')));
    await tester.pumpAndSettle();

    // 默认支出类型、默认第一个账户与第一个支出分类。
    await tester.enterText(find.byKey(const Key('txn_amount_field')), '25.80');
    await tester.tap(find.byKey(const Key('txn_save_btn')));
    await tester.pumpAndSettle();

    expect(txnRepo.added, hasLength(1));
    final input = txnRepo.added.single;
    expect(input.type, TxnType.expense);
    expect(input.accountId, 1);
    expect(input.categoryId, 10); // 第一个支出分类
    expect(input.amountMinor, 2580);
    // 对话框已关闭。
    expect(find.text('记一笔'), findsNothing);
  });

  testWidgets('切换收入类型后分类列表变为收入分类', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.byKey(const Key('add_txn_fab')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('txn_type_收入')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('txn_amount_field')), '100');
    await tester.tap(find.byKey(const Key('txn_save_btn')));
    await tester.pumpAndSettle();

    final input = txnRepo.added.single;
    expect(input.type, TxnType.income);
    expect(input.categoryId, 20); // 收入分类（工资）
  });

  testWidgets('非法金额提示且不提交', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.byKey(const Key('add_txn_fab')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('txn_amount_field')), 'abc');
    await tester.tap(find.byKey(const Key('txn_save_btn')));
    await tester.pumpAndSettle();

    expect(find.text('请输入有效金额（最多两位小数）'), findsOneWidget);
    expect(txnRepo.added, isEmpty);
  });

  testWidgets('流水列表展示交易并支持删除', (tester) async {
    await pumpPage(tester);
    // 添加一笔支出到列表。
    await txnRepo.addTransaction(
      NewTransaction(
        type: TxnType.expense,
        accountId: 1,
        categoryId: 10,
        amountMinor: 2580,
        note: '午饭',
        occurredAt: DateTime(2026, 10, 25, 12),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('txn_1')), findsOneWidget);
    expect(find.text('-25.80'), findsOneWidget);

    // 长按 → 删除。
    await tester.longPress(find.byKey(const Key('txn_1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete_txn_action')));
    await tester.pumpAndSettle();

    expect(txnRepo.deletedIds, [1]);
    expect(find.byKey(const Key('txn_1')), findsNothing);
  });

  testWidgets('编辑交易：回填并调用 update', (tester) async {
    await pumpPage(tester);
    await txnRepo.addTransaction(
      NewTransaction(
        type: TxnType.expense,
        accountId: 1,
        categoryId: 10,
        amountMinor: 2580,
        note: '午饭',
        occurredAt: DateTime(2026, 10, 25, 12),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const Key('txn_1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();

    // 回填金额（直接改值后保存，验证走 update 通道）。
    await tester.enterText(find.byKey(const Key('txn_amount_field')), '30');
    await tester.tap(find.byKey(const Key('txn_save_btn')));
    await tester.pumpAndSettle();

    expect(txnRepo.updated, hasLength(1));
    expect(txnRepo.updated.single.$1, 1);
    expect(txnRepo.updated.single.$2.amountMinor, 3000);
  });
}
