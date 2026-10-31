import 'package:worthtrack/modules/finance/domain/repositories/pin_repository.dart';

/// 内存假实现：明文存 PIN（仅测试用），并记录调用次数便于断言。
class FakePinRepository implements PinRepository {
  FakePinRepository({String? pin}) : _pin = pin;

  String? _pin;

  int setCalls = 0;
  int verifyCalls = 0;
  int clearCalls = 0;

  /// 当前 PIN（null = 未设置）。
  String? get pin => _pin;

  @override
  Future<bool> hasPin() async => _pin != null;

  @override
  Future<void> setPin(String pin) async {
    _pin = pin;
    setCalls++;
  }

  @override
  Future<bool> verifyPin(String pin) async {
    verifyCalls++;
    return _pin != null && _pin == pin;
  }

  @override
  Future<void> clearPin() async {
    _pin = null;
    clearCalls++;
  }
}
