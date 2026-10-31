import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:worthtrack/core/providers.dart';
import 'package:worthtrack/core/pin/pin_lock.dart';

/// 锁屏（issue #17）：输满 6 位即校验，失败清空重输。
///
/// 「忘记 PIN」走重置流程：清除 PIN 后直接进入应用，**不删任何账目数据**。
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key, required this.onUnlocked});

  /// 校验通过 / 重置完成后回调，由 [LockGate] 切到主界面。
  final VoidCallback onUnlocked;

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final pin = _controller.text;
    if (!isValidPin(pin)) {
      setState(() => _error = pinErrorText(pin));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });

    final ok = await ref.read(pinRepositoryProvider).verifyPin(pin);
    if (!mounted) return;
    if (ok) {
      widget.onUnlocked();
      return;
    }
    _controller.clear();
    setState(() {
      _busy = false;
      _error = 'PIN 不正确，请重试';
    });
    _focusNode.requestFocus();
  }

  Future<void> _resetPin() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重置 PIN 锁？'),
        content: const Text(
          '重置会清除 PIN 并直接进入应用。\n'
          '账户、明细、预算、持仓等数据都不会被删除，之后可以在「设置」里重新开启。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('lock_reset_confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('重置并进入'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref.read(pinRepositoryProvider).clearPin();
    if (!mounted) return;
    widget.onUnlocked();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.lock_outline,
                    size: 56,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text('输入 PIN', style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(
                    '$pinLength 位数字，输满自动解锁',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 28),
                  TextField(
                    key: const Key('lock_pin_field'),
                    controller: _controller,
                    focusNode: _focusNode,
                    autofocus: true,
                    enabled: !_busy,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      letterSpacing: 12,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(pinLength),
                    ],
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      counterText: '',
                      hintText: '••••••',
                    ),
                    onChanged: (value) {
                      if (value.length == pinLength) {
                        _submit();
                      } else if (_error != null) {
                        setState(() => _error = null);
                      }
                    },
                    onSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 24,
                    child: _error == null
                        ? null
                        : Text(
                            _error!,
                            key: const Key('lock_error'),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.error,
                            ),
                          ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    key: const Key('lock_forgot_btn'),
                    onPressed: _busy ? null : _resetPin,
                    child: const Text('忘记 PIN？'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
