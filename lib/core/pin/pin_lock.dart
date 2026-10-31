/// 启动 PIN 锁的纯逻辑（issue #17）：校验规则、加盐哈希、常量时间比对。
///
/// **威胁模型（重要）**：PIN 只防止他人随手翻看本机数据，**不加密数据库**。
/// 忘记 PIN 可以重置进入，数据不会丢失——这是有意的取舍：
/// 真要抗取证得上 SQLCipher 全库加密，v1 不做。
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// PIN 长度：固定 6 位数字（与支付密码习惯一致，输满即校验）。
const int pinLength = 6;

/// PBKDF2 迭代次数。
///
/// 6 位数字的取值空间只有 10^6，迭代次数再多也挡不住穷举；
/// 这里的作用仅是避免把明文/单次哈希落盘，2000 次约 10–20ms，解锁无感。
const int defaultPinIterations = 2000;

final RegExp _pinPattern = RegExp('^\\d{$pinLength}\$');

/// 是否为合法 PIN：恰好 6 位 ASCII 数字。
bool isValidPin(String pin) => _pinPattern.hasMatch(pin);

/// PIN 的加盐哈希记录（落盘内容）。
///
/// 只存 salt + 派生结果，**任何情况下都不存明文**。
class PinCredential {
  const PinCredential({
    required this.salt,
    required this.hash,
    this.iterations = defaultPinIterations,
  });

  /// 用给定 PIN 派生凭据；[salt] 省略时随机生成（base64）。
  factory PinCredential.derive(
    String pin, {
    String? salt,
    int iterations = defaultPinIterations,
    Random? random,
  }) {
    final useSalt = salt ?? randomSalt(random);
    final derived = _pbkdf2(
      utf8.encode(pin),
      base64Decode(useSalt),
      iterations,
      32,
    );
    return PinCredential(
      salt: useSalt,
      hash: base64Encode(derived),
      iterations: iterations,
    );
  }

  factory PinCredential.fromJson(Map<String, dynamic> json) {
    final salt = json['salt'];
    final hash = json['hash'];
    final iterations = json['iterations'];
    if (salt is! String || hash is! String) {
      throw const FormatException('PIN 记录缺少 salt/hash');
    }
    return PinCredential(
      salt: salt,
      hash: hash,
      iterations: iterations is int && iterations > 0
          ? iterations
          : defaultPinIterations,
    );
  }

  final String salt;

  /// PBKDF2-HMAC-SHA256 派生结果（base64）。
  final String hash;

  final int iterations;

  /// 校验 PIN 是否匹配（常量时间比较，避免时序侧信道）。
  bool matches(String pin) {
    if (!isValidPin(pin)) return false;
    final candidate = PinCredential.derive(
      pin,
      salt: salt,
      iterations: iterations,
    );
    return _constantTimeEquals(
      base64Decode(candidate.hash),
      base64Decode(hash),
    );
  }

  Map<String, dynamic> toJson() => {
    'salt': salt,
    'hash': hash,
    'iterations': iterations,
  };
}

/// 生成 16 字节随机盐（base64 编码）。
String randomSalt([Random? random]) {
  final rng = random ?? Random.secure();
  final bytes = Uint8List(16);
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] = rng.nextInt(256);
  }
  return base64Encode(bytes);
}

/// PBKDF2-HMAC-SHA256（RFC 2898），输出 [keyLength] 字节。
List<int> _pbkdf2(
  List<int> password,
  List<int> salt,
  int iterations,
  int keyLength,
) {
  final hmac = Hmac(sha256, password);
  final out = <int>[];
  var blockIndex = 1;
  while (out.length < keyLength) {
    final saltBlock = Uint8List.fromList([
      ...salt,
      (blockIndex >> 24) & 0xff,
      (blockIndex >> 16) & 0xff,
      (blockIndex >> 8) & 0xff,
      blockIndex & 0xff,
    ]);
    var u = hmac.convert(saltBlock).bytes;
    final t = List<int>.of(u);
    for (var i = 1; i < iterations; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < t.length; j++) {
        t[j] ^= u[j];
      }
    }
    out.addAll(t);
    blockIndex++;
  }
  return out.sublist(0, keyLength);
}

/// 逐字节比较，耗时与「第几个字节不同」无关。
bool _constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

/// 输错后的提示文案。
String pinErrorText(String input) {
  if (input.isEmpty) return '请输入 $pinLength 位数字 PIN';
  if (!isValidPin(input)) return 'PIN 必须是 $pinLength 位数字';
  return 'PIN 不正确，请重试';
}
