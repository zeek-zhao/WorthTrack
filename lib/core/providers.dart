import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'package:worthtrack/core/backup/backup_repository.dart';
import 'package:worthtrack/core/backup/database_backup_repository.dart';
import 'package:worthtrack/core/files/file_save_picker.dart';
import 'package:worthtrack/core/pin/pin_repository.dart';
import 'package:worthtrack/core/pin/pin_repository_impl.dart';
import 'package:worthtrack/core/pin/pin_store.dart';
import 'package:worthtrack/data/db/app_database.dart';

/// **core 服务的 Provider 注册点。**
///
/// 模块可以 import 这个文件（拿数据库、文件选择器这类平台能力），
/// 但**不能** import `di.dart`——那是装配入口，会反向依赖所有模块。
///
/// 模块自己的仓储请放在各自目录下（如 `modules/finance/finance_providers.dart`）。

/// 全局数据库单例。
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase(_openConnection());
  ref.onDispose(db.close);
  return db;
});

/// 启动 PIN 锁仓储（M3-#17）：凭据存应用支持目录的独立 JSON 文件，
/// **不写数据库**——忘记 PIN 重置只需删文件，账目数据分毫不动。
final pinRepositoryProvider = Provider<PinRepository>((ref) {
  return PinRepositoryImpl(FilePinStore());
});

/// 文件选择器（M4-#18 备份 / #19 CSV 导出共用）：抽出接口，
/// 测试与集成测试注入假实现即可，不必真的弹系统对话框。
final fileSavePickerProvider = Provider<FileSavePicker>((ref) {
  return const PlatformFileSavePicker();
});

/// 整库备份与恢复（M4-#18；#45 起归 core，因为备份覆盖**全部模块**的表）：
/// 导出走 `VACUUM INTO`，恢复走 ATTACH + 单事务替换。
final backupRepositoryProvider = Provider<BackupRepository>((ref) {
  return DatabaseBackupRepository(ref.watch(appDatabaseProvider));
});

/// 生产环境连接：应用支持目录下的 worthtrack.sqlite3。
LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/worthtrack.sqlite3');
    return NativeDatabase.createInBackground(file);
  });
}
