import 'package:drift/drift.dart';

import '../dao/account_dao.dart';
import '../dao/budget_dao.dart';
import '../dao/category_dao.dart';
import '../dao/position_dao.dart';
import '../dao/recurring_dao.dart';
import '../dao/transaction_dao.dart';

part 'app_database.g.dart';

// NOTE: 枚举与表定义必须与数据库类在**同一文件**。
// 实测 drift_dev 2.29–2.31（Dart 3.9 可用的最后一批版本）在表与库分离的
// 文件布局下会静默丢弃 intEnum 列（复现于最小工程）；等 Flutter 升级到
// Dart ≥3.10（可用 drift ≥2.33）后再验证拆分，当前保持单文件。

/// 账户类型：现金 / 储蓄卡 / 信用卡 / 投资账户。
enum AccountType { cash, bank, credit, investment }

/// 分类用途：支出 / 收入。
enum CategoryKind { expense, income }

/// 交易类型：支出 / 收入 / 转账。
enum TxnType { expense, income, transfer }

/// 周期账单频率。
enum RecurFrequency { daily, weekly, monthly, yearly }

/// 证券市场：沪 / 深。
enum Market { sh, sz }

/// 账户表。余额以分存储。
class Accounts extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 50)();
  IntColumn get type => intEnum<AccountType>()();

  /// 当前余额，单位：分。信用卡账户可为负。
  IntColumn get balanceMinor => integer().withDefault(const Constant(0))();
  TextColumn get note => text().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  /// 归档时间（软删除），null 表示使用中。
  DateTimeColumn get archivedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// 分类表（内置 + 自定义共用一张表）。
class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 30)();
  IntColumn get kind => intEnum<CategoryKind>()();
  TextColumn get icon => text().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  /// 父分类 id（null = 一级分类）。二级分类最多一层。
  IntColumn get parentId => integer().nullable().references(Categories, #id)();

  DateTimeColumn get archivedAt => dateTime().nullable()();
}

/// 交易流水表。金额以分存储。
class Transactions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get type => intEnum<TxnType>()();

  /// 转出/支出账户；收入时为收款账户。
  IntColumn get accountId => integer().references(Accounts, #id)();

  /// 转账目标账户，仅 transfer 类型使用。
  IntColumn get toAccountId => integer().nullable().references(Accounts, #id)();
  IntColumn get categoryId =>
      integer().nullable().references(Categories, #id)();
  IntColumn get amountMinor => integer()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get occurredAt => dateTime()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// 月度预算表。金额以分存储。
class Budgets extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get categoryId => integer().references(Categories, #id)();
  IntColumn get amountMinor => integer()();

  /// 归属月份，存当月 1 日 00:00（本地时区）。
  DateTimeColumn get month => dateTime()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<Set<Column>> get uniqueKeys => [
    {categoryId, month},
  ];
}

/// 周期账单规则表。
class RecurringRules extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 50)();
  IntColumn get type => intEnum<TxnType>()();
  IntColumn get accountId => integer().references(Accounts, #id)();
  IntColumn get categoryId =>
      integer().nullable().references(Categories, #id)();
  IntColumn get amountMinor => integer()();
  IntColumn get frequency => intEnum<RecurFrequency>()();

  /// 间隔数：每 N 天/周/月/年，默认 1。
  IntColumn get interval => integer().withDefault(const Constant(1))();
  DateTimeColumn get startDate => dateTime()();
  DateTimeColumn get nextRunAt => dateTime()();
  DateTimeColumn get endDate => dateTime().nullable()();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  TextColumn get note => text().nullable()();
}

/// 投资持仓表。份额与价格均为整数。
class Positions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get market => intEnum<Market>()();
  TextColumn get code => text().withLength(min: 6, max: 6)();
  TextColumn get name => text().withLength(min: 1, max: 30)();

  /// 持有份额，单位：0.01 份（如 15000 = 150.00 份）。
  IntColumn get sharesCent => integer()();

  /// 成本单价，单位：分。
  IntColumn get costPriceMinor => integer()();
  DateTimeColumn get archivedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<Set<Column>> get uniqueKeys => [
    {market, code},
  ];
}

/// 行情价格缓存表。断网时用缓存价计算市值。
class PriceCache extends Table {
  /// 行情代码，如 sh600519、sz159915。
  TextColumn get symbol => text()();
  IntColumn get priceMinor => integer()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {symbol};
}

/// WorthTrack 主数据库。
///
/// - 全部金额以「分」为单位的整数存储，见 lib/core/money.dart
/// - schemaVersion 从 1 起步，升级只允许在 migration 的 onUpgrade 分支追加
@DriftDatabase(
  tables: [
    Accounts,
    Categories,
    Transactions,
    Budgets,
    RecurringRules,
    Positions,
    PriceCache,
  ],
  daos: [
    AccountDao,
    TransactionDao,
    CategoryDao,
    BudgetDao,
    RecurringDao,
    PositionDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 1;

  final MigrationStrategy _migration = MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      // v1 起步：后续版本升级在此按 from 分支追加，禁止修改旧表结构历史。
      throw UnimplementedError('未处理的数据库迁移: v$from → v$to');
    },
  );

  @override
  MigrationStrategy get migration => _migration;
}
