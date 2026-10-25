import 'package:flutter/material.dart';

import 'ui/home_page.dart';

/// 应用根 Widget：Material 3 + 中文 locale。
/// 底部导航：明细 / 资产；报表、设置在 M2 加入。
class WorthTrackApp extends StatelessWidget {
  const WorthTrackApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WorthTrack',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E7D32)),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}
