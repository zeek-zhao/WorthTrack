import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worthtrack/app.dart';
import 'package:worthtrack/di.dart';

import 'helpers/fake_account_repository.dart';
import 'helpers/fake_transaction_repository.dart';

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

  testWidgets('应用启动进入底部导航（明细/资产），真实 DI 被假仓储覆盖', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountRepositoryProvider.overrideWithValue(accountRepo),
          categoryRepositoryProvider.overrideWithValue(categoryRepo),
          transactionRepositoryProvider.overrideWithValue(txnRepo),
        ],
        child: const WorthTrackApp(),
      ),
    );
    accountRepo.emit([]);
    txnRepo.emit([]);
    await tester.pumpAndSettle();

    // 底部导航两页签 + 明细页空态提示。
    expect(find.text('明细'), findsOneWidget);
    expect(find.text('资产'), findsOneWidget);
    expect(find.text('本月暂无交易，点 + 记一笔'), findsOneWidget);

    // 切到资产页。
    await tester.tap(find.text('资产'));
    await tester.pumpAndSettle();
    expect(find.text('总资产'), findsOneWidget);
  });
}
