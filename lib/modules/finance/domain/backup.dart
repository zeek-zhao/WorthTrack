/// 数据库备份与恢复的纯逻辑（issue #18）。
///
/// 这里只放**不碰 IO 的判定**：文件名生成、大小格式化、以及「一份候选文件
/// 到底能不能恢复」的校验规则。真正的读写与 SQL 编排在
/// `lib/data/backup/database_backup_repository.dart`。
///
/// 为什么不做「备份文件格式」自定义：直接导出 SQLite 库文件即可，
/// 用户拿任意 sqlite 工具都能打开核对，出问题时也不必依赖本应用解密。
library;

/// 备份文件里必须存在的表（与 `app_database.dart` 的 v1 schema 一一对应）。
///
/// 只要求**基线表**齐全：未来加了新表，旧备份依然能恢复（新表留空即可），
/// 因此这里不要随新表一起膨胀。
const Set<String> backupRequiredTables = {
  'accounts',
  'categories',
  'transactions',
  'budgets',
  'recurring_rules',
  'positions',
  'price_cache',
};

/// SQLite 文件头：`"SQLite format 3\u0000"`，共 16 字节。
const String sqliteFileHeader = 'SQLite format 3';

/// 备份文件不可恢复的原因。
enum BackupProblem {
  notFound('找不到这个文件，可能已被移动或删除'),
  empty('文件是空的，可能是复制/下载时中断了'),
  notSqlite('这不是 WorthTrack 的备份文件（不是 SQLite 数据库）'),
  missingTables('备份文件缺少必要的数据表，可能已损坏'),
  schemaNewer('备份来自更新版本的 WorthTrack，请先升级应用再恢复'),

  /// 备份的 schema 版本读不出来（`user_version <= 0`）。
  ///
  /// 注意：**「旧版本备份」不再走这个分支**——从 v2 起旧备份允许恢复（#60），
  /// 这里只拦「版本信息不可读」的异常文件。
  schemaOlder('备份的版本信息读不出来，可能已损坏'),
  sameDatabase('这是应用正在使用的账本文件，请选择一份备份文件'),
  restoreFailed('恢复过程中出错，当前数据没有被改动'),
  unreadable('读取失败，请确认文件没有被其他应用占用');

  const BackupProblem(this.message);

  /// 直接给用户看的一句话说明。
  final String message;
}

/// 校验结果：null 表示可以恢复。
///
/// 判定顺序有讲究：先排除「根本不是 SQLite」，再看表是否齐全（能挡掉
/// 拿别的 sqlite 文件来恢复的情况），最后才比 schema 版本。
BackupProblem? validateBackup({
  required int sizeBytes,
  required List<int> header,
  required Set<String> tables,
  required int fileSchemaVersion,
  required int currentSchemaVersion,
}) {
  if (sizeBytes <= 0) return BackupProblem.empty;
  if (!hasSqliteHeader(header)) return BackupProblem.notSqlite;
  if (!tables.containsAll(backupRequiredTables)) {
    return BackupProblem.missingTables;
  }
  if (fileSchemaVersion > currentSchemaVersion) {
    return BackupProblem.schemaNewer;
  }
  // 旧版本备份**允许恢复**（#60）：恢复只替换备份里真实存在的表，缺的表跳过、
  // 当前配置不被抹掉；列不匹配会让单事务整体回滚，不会写坏数据。
  //
  // 但版本号读不出来（<= 0）仍然拒绝：那说明文件不是本应用正常写出的，
  // 属于「损坏 / 不是备份」的范畴，不该拿它覆盖账本。
  if (fileSchemaVersion <= 0) {
    return BackupProblem.schemaOlder;
  }
  return null;
}

/// 文件头是否是 SQLite 魔数（`"SQLite format 3\0"` 的前 15 字节）。
bool hasSqliteHeader(List<int> header) {
  if (header.length < sqliteFileHeader.length) return false;
  for (var i = 0; i < sqliteFileHeader.length; i++) {
    if (header[i] != sqliteFileHeader.codeUnitAt(i)) return false;
  }
  return true;
}

/// 一份候选备份文件的体检结果。
class BackupInspection {
  const BackupInspection({
    required this.path,
    required this.sizeBytes,
    required this.schemaVersion,
    required this.problem,
    this.accountCount = 0,
    this.transactionCount = 0,
    this.positionCount = 0,
  });

  /// 文件绝对路径。
  final String path;

  final int sizeBytes;

  /// 文件里记录的 schema 版本（`PRAGMA user_version`）；读不出来时为 0。
  final int schemaVersion;

  /// null = 可以恢复。
  final BackupProblem? problem;

  /// 以下计数只在 [canRestore] 为真时有意义，用于恢复前的二次确认。
  final int accountCount;
  final int transactionCount;
  final int positionCount;

  bool get canRestore => problem == null;

  /// 文件名（不依赖 `package:path`，同时兼容 `/` 与 `\`）。
  String get fileName => path.split(RegExp(r'[\\/]')).last;

  /// 给用户看的一行摘要，如「worthtrack-backup-….sqlite3 · 128.0 KB」。
  String get summary => '$fileName · ${formatFileSize(sizeBytes)}';
}

/// 恢复动作本身失败（校验通过但执行出错）时抛出。
class BackupException implements Exception {
  BackupException(this.problem, {this.path, this.cause});

  final BackupProblem problem;
  final String? path;

  /// 底层异常，仅用于日志排查，不直接展示给用户。
  final Object? cause;

  @override
  String toString() =>
      'BackupException(${problem.name}${path == null ? '' : ': $path'})';
}

/// 生成备份文件名，如 `worthtrack-backup-20261028-2245.sqlite3`。
///
/// 用「年月日-时分」而不是 UUID：用户要能在文件管理器里一眼按时间排序。
String buildBackupFileName(DateTime now) {
  String two(int value) => value.toString().padLeft(2, '0');
  final date = '${now.year}${two(now.month)}${two(now.day)}';
  final time = '${two(now.hour)}${two(now.minute)}';
  return 'worthtrack-backup-$date-$time.sqlite3';
}

/// 人类可读的文件大小，如 `820 B` / `12.3 KB` / `1.4 MB`。
String formatFileSize(int bytes) {
  if (bytes < 0) return '0 B';
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(kb < 10 ? 1 : 0)} KB';
  final mb = kb / 1024;
  return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB';
}
