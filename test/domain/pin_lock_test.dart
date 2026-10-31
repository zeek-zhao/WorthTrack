import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:worthtrack/modules/finance/domain/pin_lock.dart';

/// issue #17 验收：PIN 校验规则 + 加盐哈希 + 常量时间比对。
void main() {
  group('PIN 格式', () {
    test('恰好 6 位 ASCII 数字才合法', () {
      expect(isValidPin('123456'), isTrue);
      expect(isValidPin('000000'), isTrue);
      expect(isValidPin('12345'), isFalse);
      expect(isValidPin('1234567'), isFalse);
      expect(isValidPin('12345a'), isFalse);
      expect(isValidPin('12 456'), isFalse);
      expect(isValidPin(''), isFalse);
    });

    test('全角数字不算合法', () {
      expect(isValidPin('１２３４５６'), isFalse);
    });

    test('错误文案区分空 / 位数 / 不匹配', () {
      expect(pinErrorText(''), '请输入 6 位数字 PIN');
      expect(pinErrorText('123'), 'PIN 必须是 6 位数字');
      expect(pinErrorText('123456'), 'PIN 不正确，请重试');
    });
  });

  group('凭据派生', () {
    const salt = 'c2FsdHNhbHRzYWx0c2ExMg=='; // 16 字节

    test('同 PIN 同盐派生结果稳定', () {
      final a = PinCredential.derive('123456', salt: salt, iterations: 20);
      final b = PinCredential.derive('123456', salt: salt, iterations: 20);
      expect(a.hash, b.hash);
      expect(a.salt, salt);
      expect(a.iterations, 20);
    });

    test('同 PIN 不同盐派生结果不同（防彩虹表）', () {
      final a = PinCredential.derive('123456', salt: salt, iterations: 20);
      final b = PinCredential.derive('123456', iterations: 20);
      expect(a.hash, isNot(b.hash));
    });

    test('哈希不含明文 PIN', () {
      final credential = PinCredential.derive(
        '246810',
        salt: salt,
        iterations: 20,
      );
      final encoded = jsonEncode(credential.toJson());
      expect(encoded.contains('246810'), isFalse);
      // 派生结果是 32 字节 → base64 44 字符。
      expect(base64Decode(credential.hash).length, 32);
    });

    test('默认迭代次数为 defaultPinIterations', () {
      final credential = PinCredential.derive('123456', salt: salt);
      expect(credential.iterations, defaultPinIterations);
    });

    test('matches 只接受正确 PIN，非法格式直接 false', () {
      final credential = PinCredential.derive(
        '123456',
        salt: salt,
        iterations: 20,
      );
      expect(credential.matches('123456'), isTrue);
      expect(credential.matches('123457'), isFalse);
      expect(credential.matches('12345'), isFalse);
      expect(credential.matches(''), isFalse);
    });
  });

  group('序列化', () {
    const salt = 'c2FsdHNhbHRzYWx0c2ExMg==';

    test('toJson / fromJson 往返一致', () {
      final original = PinCredential.derive(
        '123456',
        salt: salt,
        iterations: 20,
      );
      final restored = PinCredential.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
      );
      expect(restored.salt, original.salt);
      expect(restored.hash, original.hash);
      expect(restored.iterations, original.iterations);
      expect(restored.matches('123456'), isTrue);
    });

    test('缺字段抛 FormatException，迭代次数缺失回落默认值', () {
      expect(
        () => PinCredential.fromJson({'salt': salt}),
        throwsFormatException,
      );
      expect(
        () => PinCredential.fromJson({'hash': 'x'}),
        throwsFormatException,
      );
      final restored = PinCredential.fromJson({'salt': salt, 'hash': 'x'});
      expect(restored.iterations, defaultPinIterations);
    });

    test('randomSalt 每次不同且为 16 字节', () {
      final a = randomSalt();
      final b = randomSalt();
      expect(base64Decode(a).length, 16);
      expect(a, isNot(b));
    });
  });
}
