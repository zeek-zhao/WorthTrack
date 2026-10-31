import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:worthtrack/data/db/app_database.dart';
import 'package:worthtrack/modules/finance/domain/csv_export.dart';

void main() {
  CsvTransactionRow row({
    DateTime? at,
    TxnType type = TxnType.expense,
    String accountName = '工资卡',
    String? toAccountName,
    String? categoryName = '餐饮',
    int amountMinor = 2580,
    String? note = '午饭',
  }) {
    return CsvTransactionRow(
      occurredAt: at ?? DateTime(2026, 10, 20, 12),
      type: type,
      accountName: accountName,
      toAccountName: toAccountName,
      categoryName: categoryName,
      amountMinor: amountMinor,
      note: note,
    );
  }

  group('escapeCsvField', () {
    test('普通字段原样输出（中文不需要转义）', () {
      expect(escapeCsvField('午饭'), '午饭');
      expect(escapeCsvField(''), '');
      expect(escapeCsvField('KFC 早餐'), 'KFC 早餐');
    });

    test('含逗号要加引号', () {
      expect(escapeCsvField('午饭,加饮料'), '"午饭,加饮料"');
    });

    test('含双引号要加引号并把内部引号写成两个', () {
      expect(escapeCsvField('他说"太贵了"'), '"他说""太贵了"""');
    });

    test('含换行要加引号', () {
      expect(escapeCsvField('第一行\n第二行'), '"第一行\n第二行"');
      expect(escapeCsvField('a\r\nb'), '"a\r\nb"');
    });

    test('同时含逗号与引号', () {
      expect(escapeCsvField('a,"b"'), '"a,""b"""');
    });
  });

  group('formatCsvAmount', () {
    test('分转元固定两位小数', () {
      expect(formatCsvAmount(0), '0.00');
      expect(formatCsvAmount(5), '0.05');
      expect(formatCsvAmount(50), '0.50');
      expect(formatCsvAmount(2580), '25.80');
      expect(formatCsvAmount(100000), '1000.00');
    });

    test('负数保留符号（信用卡退款等场景）', () {
      expect(formatCsvAmount(-2580), '-25.80');
      expect(formatCsvAmount(-5), '-0.05');
    });
  });

  group('formatCsvTime', () {
    test('补零到分钟，不含秒', () {
      expect(formatCsvTime(DateTime(2026, 1, 2, 3, 4)), '2026-01-02 03:04');
      expect(
        formatCsvTime(DateTime(2026, 10, 20, 12, 30, 45)),
        '2026-10-20 12:30',
      );
    });
  });

  group('列值', () {
    test('交易类型中文', () {
      expect(csvTypeLabel(TxnType.expense), '支出');
      expect(csvTypeLabel(TxnType.income), '收入');
      expect(csvTypeLabel(TxnType.transfer), '转账');
    });

    test('转账账户列写成「转出 → 转入」', () {
      expect(
        csvAccountLabel(row(type: TxnType.transfer, toAccountName: '零钱')),
        '工资卡 → 零钱',
      );
    });

    test('转账缺少对方账户时退化为单账户名', () {
      expect(csvAccountLabel(row(type: TxnType.transfer)), '工资卡');
    });

    test('非转账只显示所属账户', () {
      expect(csvAccountLabel(row(toAccountName: '零钱')), '工资卡');
    });
  });

  group('buildTransactionsCsv', () {
    test('表头 + 每行 6 列，CRLF 换行，末尾留一个换行', () {
      final csv = buildTransactionsCsv([row()]);
      expect(
        csv,
        '时间,类型,账户,分类,金额,备注\r\n2026-10-20 12:00,支出,工资卡,餐饮,25.80,午饭\r\n',
      );
      expect(csv.split('\r\n').where((l) => l.isNotEmpty), hasLength(2));
    });

    test('空数据只有表头（不能变成空文件）', () {
      final csv = buildTransactionsCsv(const []);
      expect(csv, '时间,类型,账户,分类,金额,备注\r\n');
    });

    test('备注含逗号/引号/换行时整行仍然列数正确', () {
      final csv = buildTransactionsCsv([row(note: '午饭,"加饮料"\n还有甜点')]);
      final dataLine = csv.split('\r\n')[1];
      // 备注整体被引号包住，内部引号翻倍；逗号与换行因此不会拆列。
      expect(dataLine, contains('"午饭,""加饮料""\n还有甜点"'));
    });

    test('分类为空的转账行留空列，不写「null」', () {
      final csv = buildTransactionsCsv([
        row(type: TxnType.transfer, toAccountName: '零钱', categoryName: null),
      ]);
      final dataLine = csv.split('\r\n')[1];
      expect(dataLine, '2026-10-20 12:00,转账,工资卡 → 零钱,,25.80,午饭');
      expect(csv, isNot(contains('null')));
    });

    test('多行顺序保持入参顺序（调用方已按时间正序）', () {
      final csv = buildTransactionsCsv([
        row(at: DateTime(2026, 10, 1, 9), amountMinor: 100),
        row(at: DateTime(2026, 10, 2, 9), amountMinor: 200),
      ]);
      final lines = csv.split('\r\n');
      expect(lines[1], contains('2026-10-01 09:00'));
      expect(lines[2], contains('2026-10-02 09:00'));
    });
  });

  group('encodeCsvWithBom', () {
    test('前三个字节是 UTF-8 BOM', () {
      final bytes = encodeCsvWithBom('时间\n');
      expect(bytes.sublist(0, 3), csvUtf8Bom);
    });

    test('去掉 BOM 后能按 UTF-8 还原中文（Excel 靠 BOM 判定编码）', () {
      const csv = '时间,类型\r\n2026-10-20 12:00,支出\r\n';
      final bytes = encodeCsvWithBom(csv);
      expect(utf8.decode(bytes.sublist(3)), csv);
    });
  });

  test('buildCsvFileName 带年月日-时分', () {
    expect(
      buildCsvFileName(DateTime(2026, 1, 2, 3, 4)),
      'worthtrack-transactions-20260102-0304.csv',
    );
  });
}
