import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'data/backup/database_backup_repository.dart';
import 'data/db/app_database.dart';
import 'data/files/file_save_picker.dart';
import 'data/pin/pin_store.dart';
import 'data/price/tencent_price_provider.dart';
import 'data/repositories/account_repository_impl.dart';
import 'data/repositories/budget_repository_impl.dart';
import 'data/repositories/category_repository_impl.dart';
import 'data/repositories/export_repository_impl.dart';
import 'data/repositories/net_worth_repository_impl.dart';
import 'data/repositories/pin_repository_impl.dart';
import 'data/repositories/position_repository_impl.dart';
import 'data/repositories/recurring_repository_impl.dart';
import 'data/repositories/transaction_repository_impl.dart';
import 'domain/repositories/account_repository.dart';
import 'domain/repositories/backup_repository.dart';
import 'domain/repositories/budget_repository.dart';
import 'domain/repositories/category_repository.dart';
import 'domain/price_provider.dart';
import 'domain/repositories/export_repository.dart';
import 'domain/repositories/net_worth_repository.dart';
import 'domain/repositories/pin_repository.dart';
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

/// 启动 PIN 锁仓储（M3-#17）：凭据存应用支持目录的独立 JSON 文件，
/// **不写数据库**——忘记 PIN 重置只需删文件，账目数据分毫不动。
final pinRepositoryProvider = Provider<PinRepository>((ref) {
  return PinRepositoryImpl(FilePinStore());
});

/// 文件选择器（M4-#18 备份 / #19 CSV 导出共用）：抽出接口，
/// 测试与集成测试注入假实现即可，不必真的弹系统对话框。
final fileSavePickerProvider = Provider<FileSavePicker>((ref) {
  return const PlatformFileSavePicker();
});

/// 账本备份与恢复（M4-#18）：导出走 `VACUUM INTO`，恢复走 ATTACH + 单事务替换。
final backupRepositoryProvider = Provider<BackupRepository>((ref) {
  return DatabaseBackupRepository(ref.watch(appDatabaseProvider));
});

/// 交易流水 CSV 导出（M4-#19）：UTF-8 BOM，Excel 直开不乱码。
final exportRepositoryProvider = Provider<ExportRepository>((ref) {
  return ExportRepositoryImpl(ref.watch(appDatabaseProvider).transactionDao);
});

/// 生产环境连接：应用支持目录下的 worthtrack.sqlite3。
LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/worthtrack.sqlite3');
    return NativeDatabase.createInBackground(file);
  });
}
