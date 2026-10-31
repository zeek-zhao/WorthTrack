import 'dart:typed_data';

import 'package:worthtrack/domain/backup.dart';

/// 账本备份与恢复（issue #18）。
abstract class BackupRepository {
  /// 体检一份候选备份文件；不可恢复时 [BackupInspection.problem] 非 null。
  ///
  /// 只读：不会改动当前账本，也不要求文件来自本机。
  Future<BackupInspection> inspect(String path);

  /// 导出一份**一致性快照**并返回文件内容。
  ///
  /// 用 `VACUUM INTO` 而不是直接复制库文件：复制正在被写入的 SQLite 文件
  /// 可能拿到「半个事务」，而 `VACUUM INTO` 由 SQLite 保证快照一致。
  Future<Uint8List> exportBytes();

  /// 用 [sourcePath] 覆盖当前账本。
  ///
  /// 实现必须是**单事务**：要么整份换掉，要么一条不动；失败抛 [BackupException]。
  Future<void> restoreFrom(String sourcePath);
}
