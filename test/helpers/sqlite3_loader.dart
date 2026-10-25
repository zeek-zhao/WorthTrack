import 'dart:ffi';
import 'dart:io';

import 'package:sqlite3/open.dart';

/// 测试环境 SQLite3 加载器。
///
/// - CI（GitHub ubuntu runner）与多数桌面系统：直接用系统 libsqlite3.so
/// - 本地 WSL 未装 libsqlite3：回退到用户目录解包的 ~/.local/lib/libsqlite3.so
///   （见 scripts/setup_sqlite3_local.sh）
/// - 可用环境变量 WT_SQLITE3_LIB 显式指定路径
void setupSqlite3ForTests() {
  if (!Platform.isLinux) return;
  open.overrideFor(OperatingSystem.linux, () {
    final home = Platform.environment['HOME'];
    final candidates = [
      Platform.environment['WT_SQLITE3_LIB'],
      if (home != null) '$home/.local/lib/libsqlite3.so',
    ].whereType<String>().where((p) => File(p).existsSync());

    for (final path in candidates) {
      return DynamicLibrary.open(path);
    }
    return DynamicLibrary.open('libsqlite3.so');
  });
}
