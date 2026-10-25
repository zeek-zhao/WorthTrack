import 'package:flutter/material.dart';

/// 应用根 Widget：Material 3 + 中文 locale。
/// 具体页面结构在后续 issue 中替换（底部导航：明细/资产/报表/设置）。
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
      home: const _PlaceholderHomePage(),
    );
  }
}

class _PlaceholderHomePage extends StatelessWidget {
  const _PlaceholderHomePage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('WorthTrack')),
      body: const Center(child: Text('记账核心开发中（M1）')),
    );
  }
}
