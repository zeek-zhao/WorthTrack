import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:worthtrack/core/last_module_store.dart';

/// issue #44：冷启动「上次模块」的持久化与 30 分钟有效期。
///
/// 这是纯本地痕迹（不进数据库、不随备份走），所以边界必须由测试钉住：
/// 少判一个负年龄就会让「把系统时间改小」的用户永远停在旧模块。
void main() {
  group('LastModuleVisit.isFresh', () {
    final at = DateTime(2025, 1, 1, 12);

    test('刚记录时是新鲜的', () {
      expect(LastModuleVisit(moduleId: 'finance', at: at).isFresh(at), isTrue);
    });

    test('29 分 59 秒仍算新鲜', () {
      final now = at.add(const Duration(minutes: 29, seconds: 59));
      expect(LastModuleVisit(moduleId: 'finance', at: at).isFresh(now), isTrue);
    });

    test('恰好 30 分钟算新鲜（闭区间上界）', () {
      final now = at.add(const Duration(minutes: 30));
      expect(LastModuleVisit(moduleId: 'finance', at: at).isFresh(now), isTrue);
    });

    test('30 分 01 秒算过期', () {
      final now = at.add(const Duration(minutes: 30, seconds: 1));
      expect(
        LastModuleVisit(moduleId: 'finance', at: at).isFresh(now),
        isFalse,
      );
    });

    test('时钟回拨（now 早于记录时间）算过期，避免改小时间后卡在旧模块', () {
      final now = at.subtract(const Duration(seconds: 1));
      expect(
        LastModuleVisit(moduleId: 'finance', at: at).isFresh(now),
        isFalse,
      );
    });

    test('ttl 可覆盖，供测试与将来「记住更久」的开关使用', () {
      final visit = LastModuleVisit(moduleId: 'finance', at: at);
      final now = at.add(const Duration(minutes: 5));
      expect(visit.isFresh(now, ttl: const Duration(minutes: 1)), isFalse);
      expect(visit.isFresh(now, ttl: const Duration(minutes: 5)), isTrue);
    });
  });

  group('LastModuleVisit JSON', () {
    test('往返保持模块 id 与时间', () {
      final visit = LastModuleVisit(
        moduleId: 'finance',
        at: DateTime(2025, 3, 4, 5, 6, 7),
      );
      final restored = LastModuleVisit.fromJson(visit.toJson());
      expect(restored, isNotNull);
      expect(restored!.moduleId, 'finance');
      expect(restored.at, visit.at);
    });

    test('非 Map 输入返回 null', () {
      expect(LastModuleVisit.fromJson(null), isNull);
      expect(LastModuleVisit.fromJson('finance'), isNull);
      expect(LastModuleVisit.fromJson(<Object?>[]), isNull);
    });

    test('moduleId 缺失、非字符串或为空都返回 null', () {
      expect(
        LastModuleVisit.fromJson({'at': '2025-01-01T00:00:00.000'}),
        isNull,
      );
      expect(
        LastModuleVisit.fromJson({
          'moduleId': 1,
          'at': '2025-01-01T00:00:00.000',
        }),
        isNull,
      );
      expect(
        LastModuleVisit.fromJson({
          'moduleId': '',
          'at': '2025-01-01T00:00:00.000',
        }),
        isNull,
      );
    });

    test('时间无法解析时返回 null，而不是抛异常', () {
      expect(
        LastModuleVisit.fromJson({'moduleId': 'finance', 'at': '昨天'}),
        isNull,
      );
      expect(LastModuleVisit.fromJson({'moduleId': 'finance'}), isNull);
    });
  });

  group('InMemoryLastModuleStore', () {
    test('初始为空，写入后可读，clear 后回到空', () async {
      final store = InMemoryLastModuleStore();
      expect(await store.read(), isNull);

      final at = DateTime(2025, 5, 1, 9);
      await store.write('finance', at);
      final visit = await store.read();
      expect(visit?.moduleId, 'finance');
      expect(visit?.at, at);

      await store.clear();
      expect(await store.read(), isNull);
    });
  });

  group('FileLastModuleStore', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('wt_last_module');
    });

    tearDown(() async {
      await dir.delete(recursive: true);
    });

    FileLastModuleStore store() =>
        FileLastModuleStore(directory: () async => dir);

    test('文件不存在时返回 null（首次安装）', () async {
      expect(await store().read(), isNull);
    });

    test('写入后能读回，且落在 last_module.json', () async {
      final at = DateTime(2025, 2, 3, 4, 5, 6);
      await store().write('finance', at);

      final file = File('${dir.path}${Platform.pathSeparator}last_module.json');
      expect(file.existsSync(), isTrue);

      final visit = await store().read();
      expect(visit?.moduleId, 'finance');
      expect(visit?.at, at);
    });

    test('文件内容损坏时返回 null，不能挡住启动', () async {
      final file = File('${dir.path}${Platform.pathSeparator}last_module.json');
      await file.writeAsString('{ 这不是 json');

      expect(await store().read(), isNull);
    });

    test('文件是合法 JSON 但字段不对，同样返回 null', () async {
      final file = File('${dir.path}${Platform.pathSeparator}last_module.json');
      await file.writeAsString('{"moduleId": "finance"}');

      expect(await store().read(), isNull);
    });

    test('clear 删掉文件，再读为 null', () async {
      await store().write('finance', DateTime(2025, 2, 3));
      await store().clear();

      final file = File('${dir.path}${Platform.pathSeparator}last_module.json');
      expect(file.existsSync(), isFalse);
      expect(await store().read(), isNull);
    });

    test('重复写入以最后一次为准', () async {
      final s = store();
      await s.write('finance', DateTime(2025, 2, 3, 10));
      await s.write('notes', DateTime(2025, 2, 3, 11));

      final visit = await s.read();
      expect(visit?.moduleId, 'notes');
    });
  });
}
