import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'data/db/app_database.dart';
import 'data/repositories/account_repository_impl.dart';
import 'data/repositories/transaction_repository_impl.dart';
import 'domain/repositories/account_repository.dart';
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

/// 生产环境连接：应用支持目录下的 worthtrack.sqlite3。
LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/worthtrack.sqlite3');
    return NativeDatabase.createInBackground(file);
  });
}
