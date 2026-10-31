/// 交易流水 CSV 导出（issue #19）。
///
/// 目标是「双击就能用 Excel 打开、中文不乱码、字段不被逗号拆散」，所以三件事
/// 必须写死在这里，不能交给 UI 决定：
///
/// - **编码：UTF-8 带 BOM**（`EF BB BF`）。Excel 靠 BOM 判定 UTF-8，
///   没有 BOM 的 UTF-8 CSV 在中文 Windows 上会被按 GBK 解读，直接乱码。
/// - **换行：CRLF**（RFC 4180），也是 Excel 最省事的形态。
/// - **转义：字段含 `,` `"` CR LF 时整体加双引号，内部 `"` 写成 `""`**。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:worthtrack/data/db/app_database.dart';

/// UTF-8 BOM 字节。
const List<int> csvUtf8Bom = [0xEF, 0xBB, 0xBF];

/// 表头，顺序即列顺序。
const List<String> csvHeader = ['时间', '类型', '账户', '分类', '金额', '备注'];

/// 一行待导出数据：账户/分类已由 DAO 联表取好名称，这里只管排版。
class CsvTransactionRow {
  const CsvTransactionRow({
    required this.occurredAt,
    required this.type,
    required this.accountName,
    this.toAccountName,
    this.categoryName,
    required this.amountMinor,
    this.note,
  });

  final DateTime occurredAt;
  final TxnType type;

  /// 支出/收入为所属账户，转账为转出账户。
  final String accountName;

  /// 仅转账有值（转入账户）。
  final String? toAccountName;

  final String? categoryName;

  /// 金额，单位：分。导出时转成「元」并保留两位小数。
  final int amountMinor;

  final String? note;
}

/// 一次导出的结果。
class CsvExport {
  const CsvExport({
    required this.bytes,
    required this.rowCount,
    required this.generatedAt,
  });

  /// 可直接落盘的完整文件内容（含 BOM）。
  final Uint8List bytes;

  /// 数据行数（不含表头），用于提示「已导出 N 条流水」。
  final int rowCount;

  final DateTime generatedAt;
}

/// 把行渲染成 CSV 文本（不含 BOM，便于单测直接比对）。
///
/// 行顺序即入参顺序：调用方已按时间正序取数。
String buildTransactionsCsv(Iterable<CsvTransactionRow> rows) {
  final lines = <String>[csvHeader.map(escapeCsvField).join(',')];
  for (final row in rows) {
    lines.add(
      [
        formatCsvTime(row.occurredAt),
        csvTypeLabel(row.type),
        csvAccountLabel(row),
        row.categoryName ?? '',
        formatCsvAmount(row.amountMinor),
        row.note ?? '',
      ].map(escapeCsvField).join(','),
    );
  }
  return '${lines.join('\r\n')}\r\n';
}

/// CSV 字段转义（RFC 4180）。
String escapeCsvField(String value) {
  final needsQuote =
      value.contains(',') ||
      value.contains('"') ||
      value.contains('\n') ||
      value.contains('\r');
  if (!needsQuote) return value;
  return '"${value.replaceAll('"', '""')}"';
}

/// 金额：分 → 元，固定两位小数（Excel 会当数字处理，可直接求和）。
String formatCsvAmount(int amountMinor) {
  final sign = amountMinor < 0 ? '-' : '';
  final abs = amountMinor.abs();
  return '$sign${abs ~/ 100}.${(abs % 100).toString().padLeft(2, '0')}';
}

/// 时间：`2026-10-20 12:00`。精确到分钟——记账只记到分钟，秒没有信息量。
String formatCsvTime(DateTime at) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${at.year}-${two(at.month)}-${two(at.day)} '
      '${two(at.hour)}:${two(at.minute)}';
}

/// 交易类型的中文列名。
String csvTypeLabel(TxnType type) {
  return switch (type) {
    TxnType.expense => '支出',
    TxnType.income => '收入',
    TxnType.transfer => '转账',
  };
}

/// 账户列：转账写成「转出 → 转入」，一行就能看懂钱去哪了。
String csvAccountLabel(CsvTransactionRow row) {
  if (row.type != TxnType.transfer) return row.accountName;
  final to = row.toAccountName;
  if (to == null || to.isEmpty) return row.accountName;
  return '${row.accountName} → $to';
}

/// 给导出内容加上 UTF-8 BOM。
Uint8List encodeCsvWithBom(String csv) {
  return Uint8List.fromList([...csvUtf8Bom, ...utf8.encode(csv)]);
}

/// 生成导出文件名，如 `worthtrack-transactions-20261028-2245.csv`。
String buildCsvFileName(DateTime now) {
  String two(int value) => value.toString().padLeft(2, '0');
  final date = '${now.year}${two(now.month)}${two(now.day)}';
  final time = '${two(now.hour)}${two(now.minute)}';
  return 'worthtrack-transactions-$date-$time.csv';
}
