import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:worthtrack/core/module/app_module.dart';
import 'package:worthtrack/modules/finance/ui/finance_shell.dart';
import 'package:worthtrack/modules/finance/ui/transactions/transaction_edit_dialog.dart';

/// finance 模块：记账与资产（v1.0 的全部能力）。
///
/// 模块化之后它只是「一个模块」，不再假设自己是整个应用：
/// 应用级导航归 launcher，模块内部才是明细/报表/资产/投资四个 tab。
class FinanceModule extends AppModule {
  const FinanceModule();

  @override
  ModuleId get id => 'finance';

  @override
  String get name => '记账与资产';

  @override
  IconData get icon => Icons.receipt_long;

  @override
  int get defaultOrder => 10;

  /// 与 `@DriftDatabase(tables: [...])` 中的真实表一一对应（架构测试会校验）。
  /// 注意 **不包含 `module_state`**：那张表归 core。
  @override
  Set<String> get ownedTables => const {
    'accounts',
    'categories',
    'transactions',
    'budgets',
    'recurring_rules',
    'positions',
    'price_cache',
  };

  @override
  List<RouteBase> get routes => [
    GoRoute(
      path: '/finance',
      builder: (context, state) => const FinanceShell(),
    ),
  ];

  /// 「记一笔」常驻快捷：直接在 launcher 上弹记账对话框，**始终 1 步**。
  /// 走「先进模块再点 +」就是 2 步，高频动作会因此被弃用。
  @override
  List<Widget> quickActions(BuildContext context) => [
    Builder(
      builder: (context) => FilledButton.tonalIcon(
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => const TransactionEditDialog(),
        ),
        icon: const Icon(Icons.add),
        label: const Text('记一笔'),
      ),
    ),
  ];
}
