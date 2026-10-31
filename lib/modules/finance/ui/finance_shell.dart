import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:worthtrack/modules/finance/ui/accounts/accounts_page.dart';
import 'package:worthtrack/modules/finance/ui/positions/positions_page.dart';
import 'package:worthtrack/modules/finance/ui/reports/reports_page.dart';
import 'package:worthtrack/modules/finance/ui/transactions/transactions_page.dart';

/// finance 模块内部导航：明细 / 报表 / 资产 / 投资。
///
/// 这四个 tab 是**模块内部**的事，不再出现在应用级导航里（应用级是 launcher）。
/// 系统设置（PIN / 备份恢复 / 模块管理）归 core，不在这里。
class FinanceShell extends StatefulWidget {
  const FinanceShell({super.key, this.initialTab = 0});

  /// 0 明细 / 1 报表 / 2 资产 / 3 投资。
  final int initialTab;

  @override
  State<FinanceShell> createState() => _FinanceShellState();
}

class _FinanceShellState extends State<FinanceShell> {
  late int _index = widget.initialTab.clamp(0, 3);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          TransactionsPage(),
          ReportsPage(),
          AccountsPage(),
          PositionsPage(),
        ],
      ),
      bottomNavigationBar: Row(
        children: [
          // 回 launcher 的出口。桌面端没有系统返回键，所以必须给一个显式入口；
          // 它不是第 5 个 tab，模块内部仍然是四个子 tab。
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: IconButton(
              key: const Key('finance-home'),
              tooltip: '返回首页',
              icon: const Icon(Icons.grid_view_rounded),
              onPressed: () => context.go('/'),
            ),
          ),
          Expanded(
            child: NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.receipt_long_outlined),
                  selectedIcon: Icon(Icons.receipt_long),
                  label: '明细',
                ),
                NavigationDestination(
                  icon: Icon(Icons.pie_chart_outline),
                  selectedIcon: Icon(Icons.pie_chart),
                  label: '报表',
                ),
                NavigationDestination(
                  icon: Icon(Icons.account_balance_wallet_outlined),
                  selectedIcon: Icon(Icons.account_balance_wallet),
                  label: '资产',
                ),
                NavigationDestination(
                  icon: Icon(Icons.trending_up_outlined),
                  selectedIcon: Icon(Icons.trending_up),
                  label: '投资',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
