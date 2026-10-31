import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'package:worthtrack/modules/finance/domain/pin_lock.dart';

/// PIN 凭据的持久化接口。
///
/// 刻意**不进 Drift 库**：
/// - PIN 属于设备安全配置而非记账数据，放文件里可以让「忘记 PIN 重置」
///   只删文件、完全不碰数据库（#17 验收：数据不丢）；
/// - 也不用 schemaVersion 迁移，避免动老表结构。
abstract class PinStore {
  /// 读取凭据；未设置或文件损坏都返回 null（视为未开启 PIN，不锁死用户）。
  Future<PinCredential?> read();

  Future<void> write(PinCredential credential);

  Future<void> clear();
}

/// 落盘实现：`<应用支持目录>/pin_lock.json`，写入走临时文件 + rename。
class FilePinStore implements PinStore {
  FilePinStore({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directory;

  /// 文件名单独暴露，便于测试与排查。
  static const String fileName = 'pin_lock.json';

  Future<File> _file() async {
    final dir = await _directory();
    return File('${dir.path}/$fileName');
  }

  @override
  Future<PinCredential?> read() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return null;
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return null;
      return PinCredential.fromJson(json);
    } catch (_) {
      // 文件损坏 / 无读权限 / 格式升级：一律当作未设置，宁可少锁不可锁死。
      return null;
    }
  }

  @override
  Future<void> write(PinCredential credential) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    // 先写临时文件再 rename：避免写一半掉电留下半截 JSON。
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(credential.toJson()), flush: true);
    await tmp.rename(file.path);
  }

  @override
  Future<void> clear() async {
    final file = await _file();
    if (await file.exists()) {
      await file.delete();
    }
    final tmp = File('${file.path}.tmp');
    if (await tmp.exists()) {
      await tmp.delete();
    }
  }
}
