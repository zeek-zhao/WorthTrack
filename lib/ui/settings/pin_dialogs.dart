import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:worthtrack/domain/pin_lock.dart';

/// 设置/修改 PIN 的对话框：两次输入一致才返回 PIN，取消返回 null。
class PinSetupDialog extends StatefulWidget {
  const PinSetupDialog({super.key, this.title = '设置 PIN'});

  final String title;

  @override
  State<PinSetupDialog> createState() => _PinSetupDialogState();
}

class _PinSetupDialogState extends State<PinSetupDialog> {
  final TextEditingController _pin = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _pin.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _save() {
    final pin = _pin.text;
    if (!isValidPin(pin)) {
      setState(() => _error = 'PIN 必须是 $pinLength 位数字');
      return;
    }
    if (_confirm.text != pin) {
      setState(() => _error = '两次输入不一致');
      return;
    }
    Navigator.of(context).pop(pin);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('pin_new_field'),
            controller: _pin,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(pinLength),
            ],
            decoration: InputDecoration(
              labelText: '$pinLength 位数字',
              border: const OutlineInputBorder(),
              counterText: '',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('pin_confirm_field'),
            controller: _confirm,
            obscureText: true,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(pinLength),
            ],
            decoration: const InputDecoration(
              labelText: '再次输入',
              border: OutlineInputBorder(),
              counterText: '',
            ),
            onSubmitted: (_) => _save(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _error!,
                key: const Key('pin_dialog_error'),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('pin_save_btn'),
          onPressed: _save,
          child: const Text('保存'),
        ),
      ],
    );
  }
}

/// 验证当前 PIN 的对话框：通过返回 true，取消返回 null。
class PinVerifyDialog extends StatefulWidget {
  const PinVerifyDialog({
    super.key,
    required this.verify,
    this.title = '验证 PIN',
  });

  /// 交给调用方注入（生产走仓储，测试可给桩）。
  final Future<bool> Function(String pin) verify;

  final String title;

  @override
  State<PinVerifyDialog> createState() => _PinVerifyDialogState();
}

class _PinVerifyDialogState extends State<PinVerifyDialog> {
  final TextEditingController _pin = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final pin = _pin.text;
    if (!isValidPin(pin)) {
      setState(() => _error = '请输入 $pinLength 位数字 PIN');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await widget.verify(pin);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
      return;
    }
    _pin.clear();
    setState(() {
      _busy = false;
      _error = 'PIN 不正确';
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('pin_current_field'),
            controller: _pin,
            autofocus: true,
            enabled: !_busy,
            obscureText: true,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(pinLength),
            ],
            decoration: const InputDecoration(
              labelText: '当前 PIN',
              border: OutlineInputBorder(),
              counterText: '',
            ),
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _error!,
                key: const Key('pin_verify_error'),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('pin_verify_btn'),
          onPressed: _busy ? null : _submit,
          child: const Text('确认'),
        ),
      ],
    );
  }
}
