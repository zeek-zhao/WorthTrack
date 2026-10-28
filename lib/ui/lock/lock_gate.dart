import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di.dart';
import 'lock_screen.dart';

/// 启动锁门卫（issue #17）：已设 PIN 时先出锁屏，解锁后才挂载主界面。
///
/// 两个触发点：
/// 1. 冷启动：读一次 [PinRepository.hasPin]；
/// 2. 从后台回到前台：重新读一次（设置页可能刚开启/关闭 PIN），
///    有 PIN 就重新上锁——否则「锁」只在冷启动生效，切后台再回来形同虚设。
class LockGate extends ConsumerStatefulWidget {
  const LockGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<LockGate> createState() => _LockGateState();
}

class _LockGateState extends ConsumerState<LockGate>
    with WidgetsBindingObserver {
  bool _ready = false;
  bool _locked = false;
  bool _wasBackgrounded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<bool> _hasPin() async {
    try {
      return await ref.read(pinRepositoryProvider).hasPin();
    } catch (_) {
      // 读不到凭据时宁可放行：锁死用户比少锁一次更糟。
      return false;
    }
  }

  Future<void> _load() async {
    final hasPin = await _hasPin();
    if (!mounted) return;
    setState(() {
      _ready = true;
      _locked = hasPin;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _wasBackgrounded = true;
      return;
    }
    if (state == AppLifecycleState.resumed && _wasBackgrounded) {
      _wasBackgrounded = false;
      _relockIfNeeded();
    }
  }

  Future<void> _relockIfNeeded() async {
    if (_locked) return;
    final hasPin = await _hasPin();
    if (!mounted || !hasPin) return;
    setState(() => _locked = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(key: Key('lock_splash'))),
      );
    }
    if (_locked) {
      return LockScreen(onUnlocked: () => setState(() => _locked = false));
    }
    return widget.child;
  }
}
