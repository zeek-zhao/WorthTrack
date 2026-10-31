import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 「上次停留在哪个模块」的一次记录。
class LastModuleVisit {
  const LastModuleVisit({required this.moduleId, required this.at});

  final String moduleId;
  final DateTime at;

  Map<String, Object?> toJson() => {
    'moduleId': moduleId,
    'at': at.toIso8601String(),
  };

  static LastModuleVisit? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['moduleId'];
    final at = raw['at'];
    if (id is! String || id.isEmpty || at is! String) return null;
    final parsed = DateTime.tryParse(at);
    if (parsed == null) return null;
    return LastModuleVisit(moduleId: id, at: parsed);
  }

  /// 距 [now] 是否还在 [ttl] 之内。时钟回拨（`now` 早于记录时间）也算过期，
  /// 避免把系统时间改小之后一直停在旧模块。
  bool isFresh(DateTime now, {Duration ttl = defaultTtl}) {
    final age = now.difference(at);
    return !age.isNegative && age <= ttl;
  }

  static const Duration defaultTtl = Duration(minutes: 30);
}

/// 「上次模块」的持久化。
///
/// **刻意不进数据库、不随备份走**：这是设备本地的使用痕迹，
/// 换手机后从 launcher 开始更合理，也不该占用 `module_state` 这张「用户配置」表。
abstract class LastModuleStore {
  Future<LastModuleVisit?> read();

  Future<void> write(String moduleId, DateTime at);

  Future<void> clear();
}

/// 落到 `<应用支持目录>/last_module.json` 的实现。
class FileLastModuleStore implements LastModuleStore {
  FileLastModuleStore({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directory;

  Future<File> _file() async {
    final dir = await _directory();
    return File('${dir.path}${Platform.pathSeparator}last_module.json');
  }

  @override
  Future<LastModuleVisit?> read() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      return LastModuleVisit.fromJson(jsonDecode(await file.readAsString()));
    } catch (_) {
      // 文件坏了不该挡住启动：当作没有记录。
      return null;
    }
  }

  @override
  Future<void> write(String moduleId, DateTime at) async {
    try {
      final file = await _file();
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode(LastModuleVisit(moduleId: moduleId, at: at).toJson()),
      );
    } catch (_) {
      // 写失败只影响「下次冷启动停在哪」，不影响任何数据。
    }
  }

  @override
  Future<void> clear() async {
    try {
      final file = await _file();
      if (await file.exists()) await file.delete();
    } catch (_) {
      // 同上，忽略。
    }
  }
}

/// 内存实现，供测试与「不落盘」场景使用。
class InMemoryLastModuleStore implements LastModuleStore {
  LastModuleVisit? _visit;

  @override
  Future<LastModuleVisit?> read() async => _visit;

  @override
  Future<void> write(String moduleId, DateTime at) async {
    _visit = LastModuleVisit(moduleId: moduleId, at: at);
  }

  @override
  Future<void> clear() async {
    _visit = null;
  }
}
