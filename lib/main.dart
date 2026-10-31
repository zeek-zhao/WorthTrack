import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:worthtrack/app.dart';
import 'package:worthtrack/core/last_module_store.dart';
import 'package:worthtrack/core/router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 冷启动落地页：上次停留的模块若还在 30 分钟内就回到它，否则回 launcher。
  // 读失败不阻塞启动（FileLastModuleStore 内部已吞掉异常）。
  final store = FileLastModuleStore();
  final initialLocation = resolveInitialLocation(
    await store.read(),
    DateTime.now(),
  );

  runApp(ProviderScope(child: WorthTrackApp(initialLocation: initialLocation)));
}
