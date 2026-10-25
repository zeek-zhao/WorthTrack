import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worthtrack/app.dart';
import 'package:worthtrack/di.dart';

import 'helpers/fake_account_repository.dart';

void main() {
  late FakeAccountRepository fake;

  setUp(() {
    fake = FakeAccountRepository();
  });

  tearDown(() {
    fake.dispose();
  });

  testWidgets('应用启动进入资产页（真实 DI 被假仓储覆盖）', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [accountRepositoryProvider.overrideWithValue(fake)],
        child: const WorthTrackApp(),
      ),
    );
    fake.emit([]);
    await tester.pumpAndSettle();

    expect(find.text('WorthTrack'), findsOneWidget);
    expect(find.text('总资产'), findsOneWidget);
  });
}
