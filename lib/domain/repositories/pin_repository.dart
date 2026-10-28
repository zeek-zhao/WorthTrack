/// 启动 PIN 锁仓储（issue #17）。
abstract class PinRepository {
  /// 是否已设置 PIN（决定启动时是否上锁）。
  Future<bool> hasPin();

  /// 设置/覆盖 PIN（调用方需先用 [isValidPin] 校验格式）。
  Future<void> setPin(String pin);

  /// 校验 PIN。
  Future<bool> verifyPin(String pin);

  /// 清除 PIN（忘记 PIN 重置 / 主动关闭），**不动任何账目数据**。
  Future<void> clearPin();
}
