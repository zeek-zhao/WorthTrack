import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:worthtrack/data/pin/pin_store.dart';
import 'package:worthtrack/data/repositories/pin_repository_impl.dart';
import 'package:worthtrack/domain/pin_lock.dart';

/// issue #17 验收：PIN 凭据落盘、损坏容错、重置不碰数据库。
void main() {
  late Directory tempDir;
  late FilePinStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('wt_pin_');
    store = FilePinStore(directory: () async => tempDir);
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  File pinFile() => File('${tempDir.path}/${FilePinStore.fileName}');

  group('FilePinStore', () {
    test('未设置时 read 返回 null', () async {
      expect(await store.read(), isNull);
    });

    test('写入后可读回，且能校验 PIN', () async {
      await store.write(PinCredential.derive('123456', iterations: 20));
      expect(pinFile().existsSync(), isTrue);

      final loaded = await store.read();
      expect(loaded, isNotNull);
      expect(loaded!.matches('123456'), isTrue);
      expect(loaded.matches('654321'), isFalse);
    });

    test('落盘内容不含明文 PIN', () async {
      await store.write(PinCredential.derive('246810', iterations: 20));
      final raw = await pinFile().readAsString();
      expect(raw.contains('246810'), isFalse);
      final json = jsonDecode(raw) as Map<String, dynamic>;
      expect(json.keys, containsAll(<String>['salt', 'hash', 'iterations']));
    });

    test('clear 删除文件，之后再 read 为 null', () async {
      await store.write(PinCredential.derive('123456', iterations: 20));
      await store.clear();
      expect(pinFile().existsSync(), isFalse);
      expect(await store.read(), isNull);
    });

    test('文件损坏时按未设置处理（不锁死用户）', () async {
      await pinFile().writeAsString('{ 这不是 JSON');
      expect(await store.read(), isNull);

      await pinFile().writeAsString('');
      expect(await store.read(), isNull);

      await pinFile().writeAsString('[1,2,3]');
      expect(await store.read(), isNull);
    });

    test('写入走临时文件 + rename，不留 .tmp 残渣', () async {
      await store.write(PinCredential.derive('123456', iterations: 20));
      final leftovers = tempDir
          .listSync()
          .where((e) => e.path.endsWith('.tmp'))
          .toList();
      expect(leftovers, isEmpty);
    });
  });

  group('PinRepositoryImpl', () {
    late PinRepositoryImpl repo;

    setUp(() {
      repo = PinRepositoryImpl(store, iterations: 20);
    });

    test('setPin 后 hasPin 为真，verifyPin 正确/错误分别返回', () async {
      expect(await repo.hasPin(), isFalse);

      await repo.setPin('123456');
      expect(await repo.hasPin(), isTrue);
      expect(await repo.verifyPin('123456'), isTrue);
      expect(await repo.verifyPin('111111'), isFalse);
    });

    test('非法 PIN 直接抛错，不落盘', () async {
      expect(() => repo.setPin('12345'), throwsArgumentError);
      expect(() => repo.setPin('abcdef'), throwsArgumentError);
      expect(await repo.hasPin(), isFalse);
    });

    test('未设置 PIN 时 verifyPin 恒 false', () async {
      expect(await repo.verifyPin('123456'), isFalse);
    });

    test('重置（clearPin）后 verifyPin 恒 false，可重新设置', () async {
      await repo.setPin('123456');
      await repo.clearPin();
      expect(await repo.hasPin(), isFalse);
      expect(await repo.verifyPin('123456'), isFalse);

      await repo.setPin('654321');
      expect(await repo.verifyPin('654321'), isTrue);
      expect(await repo.verifyPin('123456'), isFalse);
    });

    test('重复 setPin 覆盖旧 PIN（改 PIN 语义）', () async {
      await repo.setPin('123456');
      await repo.setPin('654321');
      expect(await repo.verifyPin('123456'), isFalse);
      expect(await repo.verifyPin('654321'), isTrue);
    });
  });
}
