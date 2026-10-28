import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// 「选保存位置 / 选备份文件」的抽象（issue #18）。
///
/// 单独抽出来是为了让 UI 与集成测试都不必真的弹系统对话框：
/// 测试注入假实现即可，业务代码也不必知道 file_picker 的存在。
abstract class BackupFilePicker {
  /// 让用户选一个位置把 [bytes] 存成 [suggestedName]。
  ///
  /// 返回最终保存路径；用户取消返回 null。
  Future<String?> saveBytes({
    required String suggestedName,
    required Uint8List bytes,
  });

  /// 让用户挑一个备份文件，返回**本机可读**的路径；用户取消返回 null。
  Future<String?> pickFileToRead();
}

/// 系统对话框实现（Android 走 SAF，桌面走 xdg-desktop-portal / 原生对话框）。
class PlatformBackupFilePicker implements BackupFilePicker {
  const PlatformBackupFilePicker();

  @override
  Future<String?> saveBytes({
    required String suggestedName,
    required Uint8List bytes,
  }) async {
    // 两端语义相反，必须分开写：
    // - Android/iOS 的系统「另存为」不返回可写路径，内容得交给系统（bytes）由 SAF 落盘；
    // - 桌面端只返回用户选的路径，bytes 参数被忽略，得我们自己写。
    if (Platform.isAndroid || Platform.isIOS) {
      return FilePicker.saveFile(
        dialogTitle: '导出账本备份',
        fileName: suggestedName,
        type: FileType.any,
        bytes: bytes,
      );
    }

    final path = await FilePicker.saveFile(
      dialogTitle: '导出账本备份',
      fileName: suggestedName,
      type: FileType.any,
    );
    if (path == null) return null;
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    return path;
  }

  @override
  Future<String?> pickFileToRead() async {
    final result = await FilePicker.pickFiles(
      dialogTitle: '选择备份文件',
      type: FileType.any,
      withData: false,
    );
    // Android 上 file_picker 会把选中的文件复制到应用缓存目录，
    // 返回的 path 因此是本机可读的普通路径。
    return result?.files.singleOrNull?.path;
  }
}

extension _SingleOrNull<T> on List<T> {
  T? get singleOrNull => length == 1 ? first : null;
}
