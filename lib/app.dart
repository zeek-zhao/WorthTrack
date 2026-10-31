import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:worthtrack/core/module/module_providers.dart';
import 'package:worthtrack/core/router.dart';
import 'package:worthtrack/di.dart';
import 'package:worthtrack/ui/lock/lock_gate.dart';

/// 应用根 Widget：Material 3 + 中文 locale + go_router 导航。
///
/// 导航结构见 `lib/core/router.dart`：launcher 是首页，每个模块一个独立 branch。
/// 启动后执行周期账单补生成（issue #11），失败静默（下次启动再试）。
/// 已设 PIN 时由 [LockGate] 先拦一道锁屏（issue #17）。
class WorthTrackApp extends ConsumerStatefulWidget {
  const WorthTrackApp({super.key, this.initialLocation = '/'});

  /// 启动落地页。由 `main()` 根据「上次模块是否还在 30 分钟内」算出来。
  final String initialLocation;

  @override
  ConsumerState<WorthTrackApp> createState() => _WorthTrackAppState();
}

class _WorthTrackAppState extends ConsumerState<WorthTrackApp> {
  late final GoRouter _router = createAppRouter(
    initialLocation: widget.initialLocation,
    lastModuleStore: ref.read(lastModuleStoreProvider),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runRecurringCatchUp());
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
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
    return MaterialApp.router(
      title: 'WorthTrack',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E7D32)),
        useMaterial3: true,
      ),
      routerConfig: _router,
      builder: (context, child) =>
          LockGate(child: child ?? const SizedBox.shrink()),
    );
  }
}
