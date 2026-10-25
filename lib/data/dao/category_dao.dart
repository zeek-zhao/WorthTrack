import 'package:drift/drift.dart';

import '../db/app_database.dart';

part 'category_dao.g.dart';

/// 分类表 DAO：含预置分类 seed 与树形操作。
@DriftAccessor(tables: [Categories])
class CategoryDao extends DatabaseAccessor<AppDatabase>
    with _$CategoryDaoMixin {
  CategoryDao(super.db);

  /// 监听使用中的分类（不含归档，按 kind、sortOrder、id 排序）。
  Stream<List<Category>> watchAll({bool includeArchived = false}) {
    final query = select(categories);
    if (!includeArchived) {
      query.where((c) => c.archivedAt.isNull());
    }
    query.orderBy([
      (c) => OrderingTerm.asc(c.kind),
      (c) => OrderingTerm.asc(c.sortOrder),
      (c) => OrderingTerm.asc(c.id),
    ]);
    return query.watch();
  }

  Future<Category?> getById(int id) {
    return (select(
      categories,
    )..where((c) => c.id.equals(id))).getSingleOrNull();
  }

  Future<int> createCategory(CategoriesCompanion entry) {
    return into(categories).insert(entry);
  }

  Future<void> updateCategory(int id, CategoriesCompanion entry) {
    return (update(categories)..where((c) => c.id.equals(id))).write(entry);
  }

  /// 归档分类；若含子分类则**级联归档**（树操作保证不留孤儿可见节点）。
  Future<void> archiveCategory(int id) async {
    await attachedDatabase.transaction(() async {
      final now = DateTime.now();
      await (update(categories)..where((c) => c.id.equals(id))).write(
        CategoriesCompanion(archivedAt: Value(now)),
      );
      await (update(categories)..where((c) => c.parentId.equals(id))).write(
        CategoriesCompanion(archivedAt: Value(now)),
      );
    });
  }

  /// 恢复分类（仅恢复自身，不级联恢复子分类）。
  Future<void> unarchiveCategory(int id) {
    return (update(categories)..where((c) => c.id.equals(id))).write(
      const CategoriesCompanion(archivedAt: Value(null)),
    );
  }

  /// 分类表为空时写入预置默认分类集（幂等：只在空表时执行）。
  Future<void> ensureSeeded() async {
    final countExp = categories.id.count();
    final query = selectOnly(categories)..addColumns([countExp]);
    final count = await query.getSingle().then(
      (row) => row.read(countExp) ?? 0,
    );
    if (count > 0) {
      return;
    }
    final defaults = <CategoriesCompanion>[
      // 支出
      _seed('餐饮', CategoryKind.expense, icon: '🍜', sortOrder: 10),
      _seed('交通', CategoryKind.expense, icon: '🚌', sortOrder: 20),
      _seed('购物', CategoryKind.expense, icon: '🛒', sortOrder: 30),
      _seed('居住', CategoryKind.expense, icon: '🏠', sortOrder: 40),
      _seed('娱乐', CategoryKind.expense, icon: '🎮', sortOrder: 50),
      _seed('医疗', CategoryKind.expense, icon: '💊', sortOrder: 60),
      _seed('人情', CategoryKind.expense, icon: '🎁', sortOrder: 70),
      _seed('其他支出', CategoryKind.expense, icon: '📦', sortOrder: 90),
      // 收入
      _seed('工资', CategoryKind.income, icon: '💼', sortOrder: 10),
      _seed('理财收益', CategoryKind.income, icon: '📈', sortOrder: 20),
      _seed('红包', CategoryKind.income, icon: '🧧', sortOrder: 30),
      _seed('其他收入', CategoryKind.income, icon: '💰', sortOrder: 90),
    ];
    await batch((b) => b.insertAll(categories, defaults));
  }

  CategoriesCompanion _seed(
    String name,
    CategoryKind kind, {
    String? icon,
    int sortOrder = 0,
  }) {
    return CategoriesCompanion.insert(
      name: name,
      kind: kind,
      icon: Value(icon),
      sortOrder: Value(sortOrder),
    );
  }
}
