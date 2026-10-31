import 'package:flutter_test/flutter_test.dart';
import 'package:worthtrack/modules/finance/domain/backup.dart';

void main() {
  List<int> headerOf([String text = sqliteFileHeader]) => text.codeUnits;

  group('buildBackupFileName', () {
    test('月/日/时/分都补零到两位', () {
      expect(
        buildBackupFileName(DateTime(2026, 1, 2, 3, 4)),
        'worthtrack-backup-20260102-0304.sqlite3',
      );
    });

    test('两位数值原样输出', () {
      expect(
        buildBackupFileName(DateTime(2026, 10, 28, 22, 45)),
        'worthtrack-backup-20261028-2245.sqlite3',
      );
    });
  });

  group('formatFileSize', () {
    test('小于 1 KB 用字节', () {
      expect(formatFileSize(0), '0 B');
      expect(formatFileSize(820), '820 B');
      expect(formatFileSize(1023), '1023 B');
    });

    test('KB 保留一位小数，两位数以上取整', () {
      expect(formatFileSize(1024), '1.0 KB');
      expect(formatFileSize(1536), '1.5 KB');
      expect(formatFileSize(1024 * 12), '12 KB');
    });

    test('MB 同理', () {
      expect(formatFileSize(1024 * 1024), '1.0 MB');
      expect(formatFileSize(1024 * 1024 * 3 ~/ 2), '1.5 MB');
    });

    test('负值兜底为 0 B（不出现 -1 B 这种文案）', () {
      expect(formatFileSize(-5), '0 B');
    });
  });

  group('hasSqliteHeader', () {
    test('标准文件头通过', () {
      expect(hasSqliteHeader(headerOf()), isTrue);
    });

    test('比文件头短的一律不通过', () {
      expect(hasSqliteHeader(const []), isFalse);
      expect(hasSqliteHeader('SQLite'.codeUnits), isFalse);
    });

    test('内容不符不通过', () {
      expect(hasSqliteHeader('SQLite format 2'.codeUnits), isFalse);
      expect(hasSqliteHeader('{"json": true}'.codeUnits), isFalse);
    });
  });

  group('validateBackup', () {
    BackupProblem? check({
      int sizeBytes = 4096,
      List<int>? header,
      Set<String>? tables,
      int fileSchemaVersion = 1,
      int currentSchemaVersion = 2,
    }) {
      return validateBackup(
        sizeBytes: sizeBytes,
        header: header ?? headerOf(),
        tables: tables ?? backupRequiredTables,
        fileSchemaVersion: fileSchemaVersion,
        currentSchemaVersion: currentSchemaVersion,
      );
    }

    test('一切正常返回 null', () {
      expect(check(), isNull);
    });

    test('空文件', () {
      expect(check(sizeBytes: 0), BackupProblem.empty);
    });

    test('不是 SQLite', () {
      expect(check(header: 'hello'.codeUnits), BackupProblem.notSqlite);
    });

    test('缺表优先于版本判断（拿别的 sqlite 文件来恢复）', () {
      expect(
        check(tables: {'accounts'}, fileSchemaVersion: 99),
        BackupProblem.missingTables,
      );
    });

    test('版本更高要提示升级应用', () {
      expect(check(fileSchemaVersion: 3), BackupProblem.schemaNewer);
    });

    test('旧版本备份允许恢复（v1 备份可以在 v2 应用里还原）', () {
      expect(check(fileSchemaVersion: 1), isNull);
    });

    test('版本信息读不出来（0）要拒绝：可能已损坏，不该拿它覆盖账本', () {
      expect(check(fileSchemaVersion: 0), BackupProblem.schemaOlder);
    });

    test('多出来的表不影响恢复（新版本备份的降级场景由版本号拦截）', () {
      expect(check(tables: {...backupRequiredTables, 'extra_table'}), isNull);
    });
  });

  group('BackupInspection', () {
    test('fileName 同时兼容 Windows 与 Unix 分隔符', () {
      const win = BackupInspection(
        path: r'C:\Users\zeek\backup.sqlite3',
        sizeBytes: 2048,
        schemaVersion: 1,
        problem: null,
      );
      const unix = BackupInspection(
        path: '/storage/emulated/0/Download/backup.sqlite3',
        sizeBytes: 2048,
        schemaVersion: 1,
        problem: null,
      );
      expect(win.fileName, 'backup.sqlite3');
      expect(unix.fileName, 'backup.sqlite3');
    });

    test('summary 拼文件名与大小', () {
      const inspection = BackupInspection(
        path: '/tmp/worthtrack-backup-20261028-2245.sqlite3',
        sizeBytes: 1536,
        schemaVersion: 1,
        problem: null,
      );
      expect(
        inspection.summary,
        'worthtrack-backup-20261028-2245.sqlite3 · 1.5 KB',
      );
    });

    test('有问题时 canRestore 为 false', () {
      const bad = BackupInspection(
        path: '/tmp/x.sqlite3',
        sizeBytes: 0,
        schemaVersion: 0,
        problem: BackupProblem.empty,
      );
      expect(bad.canRestore, isFalse);
    });
  });

  test('每个 BackupProblem 都有非空中文说明', () {
    for (final problem in BackupProblem.values) {
      expect(problem.message, isNotEmpty, reason: problem.name);
    }
  });
}
