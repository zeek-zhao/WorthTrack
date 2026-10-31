import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'package:worthtrack/core/providers.dart';
import 'package:worthtrack/modules/finance/data/price/tencent_price_provider.dart';
import 'package:worthtrack/modules/finance/data/repositories/account_repository_impl.dart';
import 'package:worthtrack/modules/finance/data/repositories/budget_repository_impl.dart';
import 'package:worthtrack/modules/finance/data/repositories/category_repository_impl.dart';
import 'package:worthtrack/modules/finance/data/repositories/export_repository_impl.dart';
import 'package:worthtrack/modules/finance/data/repositories/net_worth_repository_impl.dart';
import 'package:worthtrack/modules/finance/data/repositories/position_repository_impl.dart';
import 'package:worthtrack/modules/finance/data/repositories/recurring_repository_impl.dart';
import 'package:worthtrack/modules/finance/data/repositories/transaction_repository_impl.dart';
import 'package:worthtrack/modules/finance/domain/price_provider.dart';
import 'package:worthtrack/modules/finance/domain/repositories/account_repository.dart';
import 'package:worthtrack/modules/finance/domain/repositories/budget_repository.dart';
import 'package:worthtrack/modules/finance/domain/repositories/category_repository.dart';
import 'package:worthtrack/modules/finance/domain/repositories/export_repository.dart';
import 'package:worthtrack/modules/finance/domain/repositories/net_worth_repository.dart';
import 'package:worthtrack/modules/finance/domain/repositories/position_repository.dart';
import 'package:worthtrack/modules/finance/domain/repositories/recurring_repository.dart';
import 'package:worthtrack/modules/finance/domain/repositories/transaction_repository.dart';

/// finance 模块的 Provider 注册点。
///
/// 这些仓储只服务 finance，**不属于 core**：放这里之后
/// `core/` 与 `ui/` 都不会因为它们而反向依赖 finance（#45）。
/// 装配入口 `di.dart` 会 re-export 本文件，所以调用方仍可只 import `di.dart`。

/// 账户仓储。
final accountRepositoryProvider = Provider<AccountRepository>((ref) {
  return AccountRepositoryImpl(ref.watch(appDatabaseProvider).accountDao);
});

/// 交易仓储。
final transactionRepositoryProvider = Provider<TransactionRepository>((ref) {
  return TransactionRepositoryImpl(
    ref.watch(appDatabaseProvider).transactionDao,
  );
});

/// 分类仓储。
final categoryRepositoryProvider = Provider<CategoryRepository>((ref) {
  return CategoryRepositoryImpl(ref.watch(appDatabaseProvider).categoryDao);
});

/// 预算仓储。
final budgetRepositoryProvider = Provider<BudgetRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return BudgetRepositoryImpl(db.budgetDao, db.transactionDao);
});

/// 周期账单仓储。
final recurringRepositoryProvider = Provider<RecurringRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return RecurringRepositoryImpl(db.recurringDao, db.transactionDao);
});

/// 行情源（M3-#14）：腾讯财经公开接口，无需 key。
final priceProviderProvider = Provider<PriceProvider>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return TencentPriceProvider(client: client);
});

/// 持仓仓储。
final positionRepositoryProvider = Provider<PositionRepository>((ref) {
  return PositionRepositoryImpl(
    ref.watch(appDatabaseProvider).positionDao,
    ref.watch(priceProviderProvider),
  );
});

/// 资产总览仓储（M3-#16）：账户 + 持仓 + 交易三条流合成净资产。
final netWorthRepositoryProvider = Provider<NetWorthRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return NetWorthRepositoryImpl(
    db.accountDao,
    db.transactionDao,
    ref.watch(positionRepositoryProvider),
  );
});

/// 交易流水 CSV 导出（M4-#19）：UTF-8 BOM，Excel 直开不乱码。
final exportRepositoryProvider = Provider<ExportRepository>((ref) {
  return ExportRepositoryImpl(ref.watch(appDatabaseProvider).transactionDao);
});
