import 'dart:typed_data';

import 'package:worthtrack/core/files/file_save_picker.dart';

/// 文件选择器的假实现：直接把预设路径返回给调用方。
class FakeFileSavePicker implements FileSavePicker {
  /// 导出时「用户选的保存路径」；null 表示用户取消。
  String? savePath = '/tmp/worthtrack-backup.sqlite3';

  /// 恢复时「用户选的备份文件路径」；null 表示用户取消。
  String? openPath = '/tmp/picked-backup.sqlite3';

  int saveCalls = 0;
  int openCalls = 0;
  String? lastSuggestedName;
  Uint8List? lastBytes;

  @override
  Future<String?> saveBytes({
    required String suggestedName,
    required Uint8List bytes,
  }) async {
    saveCalls++;
    lastSuggestedName = suggestedName;
    lastBytes = bytes;
    return savePath;
  }

  @override
  Future<String?> pickFileToRead() async {
    openCalls++;
    return openPath;
  }
}
