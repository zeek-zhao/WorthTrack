import 'package:flutter_test/flutter_test.dart';
import 'package:worthtrack/data/db/app_database.dart';
import 'package:worthtrack/modules/finance/domain/net_worth.dart';
import 'package:worthtrack/modules/finance/domain/position_valuation.dart';

/// issue #16 验收：现金+储蓄+投资汇总口径、历史净资产回溯（纯函数）。
void main() {
  Position position({
    int id = 1,
    Market market = Market.sh,
    String code = '600519',
    int sharesCent = 15000,
    int costPriceMinor = 160000,
    DateTime? createdAt,
  }) => Position(
    id: id,
    market: market,
    code: code,
    name: '测试持仓',
    sharesCent: sharesCent,
    costPriceMinor: costPriceMinor,
    archivedAt: null,
    createdAt: createdAt ?? DateTime(2026, 8, 1),
  );

  Account account(
    int id,
    AccountType type,
    int balanceMinor, {
    DateTime? createdAt,
  }) => Account(
    id: id,
    name: '账户$id',
    type: type,
    balanceMinor: balanceMinor,
    note: null,
    sortOrder: 0,
    archivedAt: null,
    createdAt: createdAt ?? DateTime(2026, 8, 1),
  );

  group('资产拆分', () {
    test('现金类 = 现金 + 储蓄卡 + 信用卡（信用卡负余额抵减）', () {
      final accounts = [
        account(1, AccountType.cash, 10000),
        account(2, AccountType.bank, 500000),
        account(3, AccountType.credit, -120000),
        account(4, AccountType.investment, 999999),
      ];

      expect(cashLikeBalanceMinor(accounts), 390000);
    });

    test('投资账户余额单独统计，不计入现金类', () {
      final accounts = [
        account(1, AccountType.cash, 10000),
        account(2, AccountType.investment, 880000),
      ];

      expect(cashLikeBalanceMinor(accounts), 10000);
      expect(investmentAccountBalanceMinor(accounts), 880000);
    });

    test('投资市值只累加有现价的持仓，无价持仓单独计数', () {
      final valuations = [
        PositionValuation(
          position: position(sharesCent: 15000),
          priceMinor: 170000,
        ), // 150 × 1700 = 255000 元
        PositionValuation(
          position: position(id: 2, code: '159915', sharesCent: 100000),
          priceMinor: 1300,
        ), // 1000 × 13 = 13000 元
        PositionValuation(position: position(id: 3, code: '000001')),
      ];

      expect(investmentValueMinor(valuations), 25500000 + 1300000);
      expect(unpricedPositionCount(valuations), 1);
    });

    test('净资产 = 现金类 + 投资市值，投资账户余额不参与', () {
      final accounts = [
        account(1, AccountType.bank, 500000),
        account(2, AccountType.investment, 880000),
      ];
      final valuations = [
        PositionValuation(
          position: position(sharesCent: 15000),
          priceMinor: 170000,
        ),
      ];

      final overview = AssetOverview(
        cashMinor: cashLikeBalanceMinor(accounts),
        investmentMinor: investmentValueMinor(valuations),
        investmentAccountBalanceMinor: investmentAccountBalanceMinor(accounts),
        unpricedPositionCount: unpricedPositionCount(valuations),
        series: const [],
      );

      expect(overview.netWorthMinor, 500000 + 25500000);
      expect(overview.investmentAccountBalanceMinor, 880000);
    });

    test('空账本 isEmpty', () {
      expect(AssetOverview.empty.isEmpty, isTrue);
      expect(AssetOverview.empty.netWorthMinor, 0);
    });
  });

  group('交易对净资产的影响', () {
    test('支出为负、收入为正、转账为 0', () {
      expect(netWorthDeltaMinor(TxnType.expense, 3000), -3000);
      expect(netWorthDeltaMinor(TxnType.income, 3000), 3000);
      expect(netWorthDeltaMinor(TxnType.transfer, 3000), 0);
    });
  });

  group('历史净资产回溯', () {
    final anchor = DateTime(2026, 10, 28);

    test('无任何账目时返回空序列', () {
      final series = buildMonthlyNetWorthSeries(
        currentNetWorthMinor: 0,
        transactions: const [],
        positions: const [],
        accounts: const [],
        anchor: anchor,
        months: 12,
      );

      expect(series, isEmpty);
    });

    test('只有本月账目时裁掉前面空档，只剩一个点', () {
      final series = buildMonthlyNetWorthSeries(
        currentNetWorthMinor: 100000,
        transactions: const [],
        positions: const [],
        accounts: [
          NetWorthAccount(
            createdAt: DateTime(2026, 10, 3),
            balanceMinor: 100000,
          ),
        ],
        anchor: anchor,
        months: 12,
      );

      expect(series.length, 1);
      expect(series.single.month, DateTime(2026, 10));
      expect(series.single.netWorthMinor, 100000);
    });

    test('支出回溯：发生支出之前的月份净资产更高', () {
      final series = buildMonthlyNetWorthSeries(
        currentNetWorthMinor: 100000,
        transactions: [
          NetWorthTxn(
            occurredAt: DateTime(2026, 10, 5),
            type: TxnType.expense,
            amountMinor: 30000,
          ),
        ],
        positions: const [],
        accounts: [
          NetWorthAccount(
            createdAt: DateTime(2026, 8, 1),
            balanceMinor: 100000,
          ),
        ],
        anchor: anchor,
        months: 3,
      );

      expect(series.map((p) => p.month).toList(), [
        DateTime(2026, 8),
        DateTime(2026, 9),
        DateTime(2026, 10),
      ]);
      // 8、9 月还没花这笔钱 → 100000 + 30000；10 月已花 → 100000。
      expect(series[0].netWorthMinor, 130000);
      expect(series[1].netWorthMinor, 130000);
      expect(series[2].netWorthMinor, 100000);
    });

    test('收入回溯：发生收入之前的月份净资产更低', () {
      final series = buildMonthlyNetWorthSeries(
        currentNetWorthMinor: 50000,
        transactions: [
          NetWorthTxn(
            occurredAt: DateTime(2026, 9, 20),
            type: TxnType.income,
            amountMinor: 20000,
          ),
        ],
        positions: const [],
        accounts: [
          NetWorthAccount(createdAt: DateTime(2026, 8, 1), balanceMinor: 50000),
        ],
        anchor: anchor,
        months: 3,
      );

      expect(series[0].netWorthMinor, 30000);
      expect(series[1].netWorthMinor, 50000);
      expect(series[2].netWorthMinor, 50000);
    });

    test('转账不影响净资产（内部搬运）', () {
      final series = buildMonthlyNetWorthSeries(
        currentNetWorthMinor: 100000,
        transactions: [
          NetWorthTxn(
            occurredAt: DateTime(2026, 10, 8),
            type: TxnType.transfer,
            amountMinor: 40000,
          ),
        ],
        positions: const [],
        accounts: [
          NetWorthAccount(
            createdAt: DateTime(2026, 8, 1),
            balanceMinor: 100000,
          ),
        ],
        anchor: anchor,
        months: 3,
      );

      expect(series.every((p) => p.netWorthMinor == 100000), isTrue);
    });

    test('本月才建立的持仓不计入历史月份', () {
      final series = buildMonthlyNetWorthSeries(
        currentNetWorthMinor: 150000,
        transactions: const [],
        positions: [
          NetWorthPosition(
            createdAt: DateTime(2026, 10, 2),
            marketValueMinor: 50000,
          ),
        ],
        accounts: [
          NetWorthAccount(
            createdAt: DateTime(2026, 8, 1),
            balanceMinor: 100000,
          ),
        ],
        anchor: anchor,
        months: 3,
      );

      expect(series[0].netWorthMinor, 100000);
      expect(series[1].netWorthMinor, 100000);
      expect(series[2].netWorthMinor, 150000);
    });

    test('本月才创建的账户余额不计入历史月份', () {
      final series = buildMonthlyNetWorthSeries(
        currentNetWorthMinor: 70000,
        transactions: const [],
        positions: const [],
        accounts: [
          NetWorthAccount(createdAt: DateTime(2026, 8, 1), balanceMinor: 50000),
          NetWorthAccount(
            createdAt: DateTime(2026, 9, 15),
            balanceMinor: 20000,
          ),
        ],
        anchor: anchor,
        months: 3,
      );

      expect(series[0].netWorthMinor, 50000);
      expect(series[1].netWorthMinor, 70000);
      expect(series[2].netWorthMinor, 70000);
    });

    test('序列升序且末位为当前月', () {
      final series = buildMonthlyNetWorthSeries(
        currentNetWorthMinor: 10000,
        transactions: const [],
        positions: const [],
        accounts: [
          NetWorthAccount(
            createdAt: DateTime(2025, 11, 1),
            balanceMinor: 10000,
          ),
        ],
        anchor: anchor,
        months: 12,
      );

      expect(series.length, 12);
      expect(series.first.month, DateTime(2025, 11));
      expect(series.last.month, DateTime(2026, 10));
      for (var i = 1; i < series.length; i++) {
        expect(series[i].month.isAfter(series[i - 1].month), isTrue);
      }
    });
  });

  group('展示格式', () {
    test('紧凑金额：万 / 亿 / 元', () {
      expect(formatCompactYuan(0), '0');
      expect(formatCompactYuan(560000), '5600');
      expect(formatCompactYuan(1200000), '1.2万');
      expect(formatCompactYuan(340000000), '340.0万');
      expect(formatCompactYuan(34000000000), '3.4亿');
      expect(formatCompactYuan(-1200000), '-1.2万');
    });

    test('环比文案：含金额与百分比', () {
      final series = [
        NetWorthPoint(month: _sep, netWorthMinor: 100000),
        NetWorthPoint(month: _oct, netWorthMinor: 102000),
      ];

      expect(formatSeriesChange(series), '较上月 +¥20.00（+2.00%）');
    });

    test('环比文案：上月为 0 时省略百分比，不足两点返回 null', () {
      expect(
        formatSeriesChange([
          NetWorthPoint(month: _sep, netWorthMinor: 0),
          NetWorthPoint(month: _oct, netWorthMinor: 5000),
        ]),
        '较上月 +¥50.00',
      );
      expect(
        formatSeriesChange([NetWorthPoint(month: _oct, netWorthMinor: 5000)]),
        isNull,
      );
    });
  });
}

final _sep = DateTime(2026, 9);
final _oct = DateTime(2026, 10);
