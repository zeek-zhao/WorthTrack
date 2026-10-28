import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'data/db/app_database.dart';
import 'data/price/tencent_price_provider.dart';
import 'data/repositories/account_repository_impl.dart';
import 'data/repositories/budget_repository_impl.dart';
import 'data/repositories/category_repository_impl.dart';
import 'data/repositories/net_worth_repository_impl.dart';
import 'data/repositories/position_repository_impl.dart';
import 'data/repositories/recurring_repository_impl.dart';
import 'data/repositories/transaction_repository_impl.dart';
import 'domain/repositories/account_repository.dart';
import 'domain/repositories/budget_repository.dart';
import 'domain/repositories/category_repository.dart';
import 'domain/price_provider.dart';
import 'domain/repositories/net_worth_repository.dart';
import 'domain/repositories/position_repository.dart';
import 'domain/repositories/recurring_repository.dart';
import 'domain/repositories/transaction_repository.dart';

/// 全局数据库单例。
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase(_openConnection());
  ref.onDispose(db.close);
  return db;
});

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

/// 生产环境连接：应用支持目录下的 worthtrack.sqlite3。
LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/worthtrack.sqlite3');
    return NativeDatabase.createInBackground(file);
  });
}
