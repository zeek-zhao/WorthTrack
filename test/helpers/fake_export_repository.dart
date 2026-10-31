import 'dart:typed_data';

import 'package:worthtrack/modules/finance/domain/csv_export.dart';
import 'package:worthtrack/modules/finance/domain/repositories/export_repository.dart';

/// CSV 导出仓储的假实现。
class FakeExportRepository implements ExportRepository {
  FakeExportRepository({this.rowCount = 3, this.error});

  int rowCount;

  /// 非 null 时抛异常，用于测导出失败的提示。
  Object? error;

  int calls = 0;

  @override
  Future<CsvExport> transactionsCsv() async {
    calls++;
    final failure = error;
    if (failure != null) throw failure;
    return CsvExport(
      // BOM + 'a'，只关心「内容有没有原样交给保存对话框」。
      bytes: Uint8List.fromList([...csvUtf8Bom, 0x61]),
      rowCount: rowCount,
      generatedAt: DateTime(2026, 10, 28, 22, 45),
    );
  }
}
