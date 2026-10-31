import 'package:worthtrack/modules/finance/domain/csv_export.dart';
import 'package:worthtrack/modules/finance/domain/repositories/export_repository.dart';
import 'package:worthtrack/modules/finance/data/dao/transaction_dao.dart';

/// [ExportRepository] 实现：取数 → 排版 → 加 BOM，全部是纯拼接，没有副作用。
class ExportRepositoryImpl implements ExportRepository {
  ExportRepositoryImpl(this._dao, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final TransactionDao _dao;

  /// 注入时钟，便于测试固定文件名与 `generatedAt`。
  final DateTime Function() _now;

  @override
  Future<CsvExport> transactionsCsv() async {
    final rows = await _dao.getForExport();
    return CsvExport(
      bytes: encodeCsvWithBom(buildTransactionsCsv(rows)),
      rowCount: rows.length,
      generatedAt: _now(),
    );
  }
}
