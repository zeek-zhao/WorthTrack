import '../csv_export.dart';

/// 数据导出（issue #19）。
///
/// 与 [BackupRepository] 分开：备份是「整库快照、可还原」，导出是
/// 「给人看/给 Excel 算的一次性副本」，前者要能恢复，后者不需要。
abstract class ExportRepository {
  /// 导出全部交易流水为 CSV（UTF-8 BOM，按时间正序）。
  Future<CsvExport> transactionsCsv();
}
