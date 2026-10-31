import 'package:worthtrack/core/pin/pin_lock.dart';
import 'package:worthtrack/core/pin/pin_repository.dart';
import 'package:worthtrack/core/pin/pin_store.dart';

/// [PinRepository] 实现：只做「派生哈希 / 比对 / 落盘」，不含 UI 逻辑。
class PinRepositoryImpl implements PinRepository {
  PinRepositoryImpl(this._store, {this.iterations = defaultPinIterations});

  final PinStore _store;
  final int iterations;

  @override
  Future<bool> hasPin() async => await _store.read() != null;

  @override
  Future<void> setPin(String pin) async {
    if (!isValidPin(pin)) {
      throw ArgumentError.value(pin, 'pin', 'PIN 必须是 $pinLength 位数字');
    }
    await _store.write(PinCredential.derive(pin, iterations: iterations));
  }

  @override
  Future<bool> verifyPin(String pin) async {
    final credential = await _store.read();
    if (credential == null) return false;
    return credential.matches(pin);
  }

  @override
  Future<void> clearPin() => _store.clear();
}
