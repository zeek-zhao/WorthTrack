import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'di.dart';
import 'ui/home_page.dart';

/// 应用根 Widget：Material 3 + 中文 locale。
/// 底部导航：明细 / 报表 / 资产。
/// 启动后执行周期账单补生成（issue #11），失败静默（下次启动再试）。
class WorthTrackApp extends ConsumerStatefulWidget {
  const WorthTrackApp({super.key});

  @override
  ConsumerState<WorthTrackApp> createState() => _WorthTrackAppState();
}

class _WorthTrackAppState extends ConsumerState<WorthTrackApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runRecurringCatchUp());
  }

  Future<void> _runRecurringCatchUp() async {
    try {
      final repo = ref.read(recurringRepositoryProvider);
      await repo.catchUp(DateTime.now());
    } catch (_) {
      // 数据库未就绪或补生成失败：不阻塞启动，下次启动自动重试。
    }
  }

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
