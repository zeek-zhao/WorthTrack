import 'dart:io';
import 'dart:typed_data';

import 'package:worthtrack/modules/finance/domain/backup.dart';
import 'package:worthtrack/modules/finance/domain/repositories/backup_repository.dart';
import 'package:worthtrack/data/db/app_database.dart';

/// [BackupRepository] 的 SQLite 实现（issue #18）。
///
/// 两条关键设计：
///
/// 1. **导出用 `VACUUM INTO`**，不是复制库文件。应用运行时库文件随时可能被写入，
///    直接 `File.copy` 有机会拿到「半个事务」；`VACUUM INTO` 由 SQLite 保证
///    导出的是一致快照，顺带把碎片也整理了。
/// 2. **恢复用 `ATTACH` + 单事务整体替换**，不是「关库 → 覆盖文件 → 重开库」。
///    后者要求 UI 层重建所有 Provider、正在显示的流会断掉，而且覆盖到一半失败
///    就彻底没救了。ATTACH 方案下：连接不断、drift 的 watch 流自动收到变更、
///    中途任何一步失败事务整体回滚（#18「恢复前二次确认」之外的第二道保险）。
class DatabaseBackupRepository implements BackupRepository {
  DatabaseBackupRepository(
    this._db, {
    Future<Directory> Function()? tempDirectory,
  }) : _tempDirectory = tempDirectory ?? (() async => Directory.systemTemp);

  final AppDatabase _db;

  /// 导出快照的临时目录（测试可注入）。
  final Future<Directory> Function() _tempDirectory;

  /// 每次 ATTACH 换一个别名：体检与恢复并发时不会撞名。
  int _aliasSeq = 0;

  /// 清空顺序：先子表后父表（虽然 `defer_foreign_keys` 让顺序不再致命，
  /// 但保持正确顺序，读代码的人不必再去确认那条 PRAGMA 是否生效）。
  static const List<String> _clearOrder = [
    'transactions',
    'budgets',
    'recurring_rules',
    'positions',
    'price_cache',
    'categories',
    'accounts',
  ];

  /// 写入顺序：先父表后子表。
  static const List<String> _loadOrder = [
    'accounts',
    'categories',
    'transactions',
    'budgets',
    'recurring_rules',
    'positions',
    'price_cache',
  ];

  @override
  Future<Uint8List> exportBytes() async {
    final dir = await _tempDirectory();
    await dir.create(recursive: true);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final tmp = File('${dir.path}/worthtrack-export-$stamp.sqlite3');
    try {
      // VACUUM INTO 要求目标文件不存在；文件名带微秒时间戳，天然不重复。
      await _db.customStatement('VACUUM INTO ?', [tmp.path]);
      return await tmp.readAsBytes();
    } finally {
      await _deleteQuietly(tmp);
    }
  }

  @override
  Future<BackupInspection> inspect(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      return _result(path, 0, 0, BackupProblem.notFound);
    }
    final size = await file.length();
    final header = await _readHeader(file);

    // 连库都打不开的情况先拦掉，免得白跑一次 ATTACH。
    // 传空表集合 + 版本 0，让统一判定只可能给出「空文件」或「不是 SQLite」。
    if (size <= 0 || !hasSqliteHeader(header)) {
      return _result(
        path,
        size,
        0,
        validateBackup(
          sizeBytes: size,
          header: header,
          tables: const {},
          fileSchemaVersion: 0,
          currentSchemaVersion: _db.schemaVersion,
        ),
      );
    }

    final alias = _nextAlias();
    try {
      await _db.customStatement('ATTACH DATABASE ? AS $alias', [path]);
    } catch (_) {
      return _result(path, size, 0, BackupProblem.notSqlite);
    }

    try {
      final int schemaVersion;
      final Set<String> tables;
      try {
        final versionRows = await _db
            .customSelect('PRAGMA $alias.user_version')
            .get();
        schemaVersion = versionRows.isEmpty
            ? 0
            : versionRows.first.read<int>('user_version');
        final tableRows = await _db
            .customSelect(
              "SELECT name FROM $alias.sqlite_master WHERE type = 'table'",
            )
            .get();
        tables = {for (final row in tableRows) row.read<String>('name')};
      } catch (_) {
        // 头部像 SQLite，但读元数据就炸了 → 文件被截断或损坏。
        return _result(path, size, 0, BackupProblem.missingTables);
      }

      final problem = validateBackup(
        sizeBytes: size,
        header: header,
        tables: tables,
        fileSchemaVersion: schemaVersion,
        currentSchemaVersion: _db.schemaVersion,
      );
      if (problem != null) return _result(path, size, schemaVersion, problem);

      return BackupInspection(
        path: path,
        sizeBytes: size,
        schemaVersion: schemaVersion,
        problem: null,
        accountCount: await _count(alias, 'accounts'),
        transactionCount: await _count(alias, 'transactions'),
        positionCount: await _count(alias, 'positions'),
      );
    } finally {
      await _detachQuietly(alias);
    }
  }

  @override
  Future<void> restoreFrom(String sourcePath) async {
    if (await _isLiveDatabase(sourcePath)) {
      throw BackupException(BackupProblem.sameDatabase, path: sourcePath);
    }

    final inspection = await inspect(sourcePath);
    if (!inspection.canRestore) {
      throw BackupException(inspection.problem!, path: sourcePath);
    }

    final alias = _nextAlias();
    try {
      await _db.customStatement('ATTACH DATABASE ? AS $alias', [sourcePath]);
    } catch (e) {
      throw BackupException(
        BackupProblem.notSqlite,
        path: sourcePath,
        cause: e,
      );
    }

    try {
      await _db.transaction(() async {
        // 表间有外键（categories 还自引用），提交前不逐个校验，
        // 否则「先清父表还是先清子表」这种顺序问题会直接变成失败。
        await _db.customStatement('PRAGMA defer_foreign_keys = ON');
        for (final table in _clearOrder) {
          await _db.customStatement('DELETE FROM "$table"');
        }
        for (final table in _loadOrder) {
          await _db.customStatement(
            'INSERT INTO "$table" SELECT * FROM $alias."$table"',
          );
        }
      });
    } catch (e) {
      throw BackupException(
        BackupProblem.restoreFailed,
        path: sourcePath,
        cause: e,
      );
    } finally {
      await _detachQuietly(alias);
    }
  }

  /// 判断 [path] 是不是应用当前正在用的库文件（拿它自己恢复等于先删再读，会清空账本）。
  Future<bool> _isLiveDatabase(String path) async {
    final String live;
    try {
      final rows = await _db.customSelect('PRAGMA database_list').get();
      live = rows
          .firstWhere((row) => row.read<String>('name') == 'main')
          .read<String>('file');
    } catch (_) {
      return false;
    }
    if (live.isEmpty) return false; // 内存库，不可能撞上
    return _resolve(live) == _resolve(path);
  }

  String _resolve(String path) {
    try {
      return File(path).resolveSymbolicLinksSync();
    } catch (_) {
      return File(path).absolute.path;
    }
  }

  Future<List<int>> _readHeader(File file) async {
    final handle = await file.open();
    try {
      return await handle.read(sqliteFileHeader.length);
    } finally {
      await handle.close();
    }
  }

  Future<int> _count(String alias, String table) async {
    final rows = await _db
        .customSelect('SELECT COUNT(*) AS c FROM $alias."$table"')
        .get();
    return rows.first.read<int>('c');
  }

  BackupInspection _result(
    String path,
    int size,
    int schemaVersion,
    BackupProblem? problem,
  ) {
    return BackupInspection(
      path: path,
      sizeBytes: size,
      schemaVersion: schemaVersion,
      problem: problem,
    );
  }

  String _nextAlias() => 'bak_${_aliasSeq++}';

  Future<void> _detachQuietly(String alias) async {
    try {
      await _db.customStatement('DETACH DATABASE $alias');
    } catch (_) {
      // 语句句柄已释放时 DETACH 偶尔会报 busy；连接随应用生命周期结束，
      // 这里吞掉不影响正确性，抛出去反而会盖掉真正的失败原因。
      return;
    }
  }

  Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // 临时文件删不掉不影响导出结果，系统会自行清理缓存目录。
      return;
    }
  }
}
