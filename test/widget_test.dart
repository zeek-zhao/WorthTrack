import 'package:flutter_test/flutter_test.dart';

import 'package:worthtrack/app.dart';

void main() {
  testWidgets('app boots and shows placeholder home', (tester) async {
    await tester.pumpWidget(const WorthTrackApp());
    expect(find.text('WorthTrack'), findsOneWidget);
    expect(find.text('记账核心开发中（M1）'), findsOneWidget);
  });
}
