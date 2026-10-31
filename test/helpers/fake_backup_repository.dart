import 'dart:typed_data';

import 'package:worthtrack/modules/finance/domain/backup.dart';
import 'package:worthtrack/modules/finance/domain/repositories/backup_repository.dart';

/// 备份仓储的假实现：不碰 SQLite，只记录调用并返回预设结果。
class FakeBackupRepository implements BackupRepository {
  FakeBackupRepository({
    BackupInspection? inspection,
    Uint8List? exportContent,
    this.restoreError,
  }) : _inspection = inspection,
       exportContent = exportContent ?? Uint8List.fromList([1, 2, 3, 4]);

  BackupInspection? _inspection;

  /// 导出返回的字节（UI 只关心长度，用来拼提示文案）。
  Uint8List exportContent;

  /// 非 null 时 [exportBytes] 抛这个异常，用于测导出失败的提示。
  Object? exportError;

  /// 非 null 时 [restoreFrom] 抛这个异常，用于测「失败不改数据」的提示。
  Object? restoreError;

  int exportCalls = 0;
  int inspectCalls = 0;
  int restoreCalls = 0;
  String? restoredPath;

  /// 换一份体检结果（默认是一份「可恢复、2 账户 5 流水 1 持仓」的备份）。
  set inspection(BackupInspection value) => _inspection = value;

  @override
  Future<Uint8List> exportBytes() async {
    exportCalls++;
    final error = exportError;
    if (error != null) throw error;
    return exportContent;
  }

  @override
  Future<BackupInspection> inspect(String path) async {
    inspectCalls++;
    return _inspection ??
        BackupInspection(
          path: path,
          sizeBytes: 131072,
          schemaVersion: 1,
          problem: null,
          accountCount: 2,
          transactionCount: 5,
          positionCount: 1,
        );
  }

  @override
  Future<void> restoreFrom(String sourcePath) async {
    restoreCalls++;
    restoredPath = sourcePath;
    final error = restoreError;
    if (error != null) throw error;
  }
}
