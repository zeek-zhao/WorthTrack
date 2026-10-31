import 'package:drift/drift.dart';

import 'package:worthtrack/modules/finance/domain/repositories/category_repository.dart';
import 'package:worthtrack/modules/finance/data/dao/category_dao.dart';
import 'package:worthtrack/data/db/app_database.dart';

/// [CategoryRepository] 的 Drift 实现。
class CategoryRepositoryImpl implements CategoryRepository {
  CategoryRepositoryImpl(this._dao);

  final CategoryDao _dao;

  @override
  Stream<List<Category>> watchAll() => _dao.watchAll();

  @override
  Future<Category?> getById(int id) => _dao.getById(id);

  @override
  Future<int> createCategory({
    required String name,
    required CategoryKind kind,
    String? icon,
    int? parentId,
    int sortOrder = 0,
  }) async {
    // 二级分类的父分类必须是一级（parentId == null）。
    if (parentId != null) {
      final parent = await _dao.getById(parentId);
      if (parent == null) {
        throw ArgumentError('父分类不存在: $parentId');
      }
      if (parent.parentId != null) {
        throw ArgumentError('只支持两级分类，父分类不能是二级分类');
      }
      if (parent.kind != kind) {
        throw ArgumentError('子分类用途必须与父分类一致');
      }
    }
    return _dao.createCategory(
      CategoriesCompanion.insert(
        name: name,
        kind: kind,
        icon: Value(icon),
        parentId: Value(parentId),
        sortOrder: Value(sortOrder),
      ),
    );
  }

  @override
  Future<void> updateCategory({
    required int id,
    String? name,
    String? icon,
    int? sortOrder,
  }) {
    return _dao.updateCategory(
      id,
      CategoriesCompanion(
        name: name == null ? const Value.absent() : Value(name),
        icon: icon == null ? const Value.absent() : Value(icon),
        sortOrder: sortOrder == null ? const Value.absent() : Value(sortOrder),
      ),
    );
  }

  @override
  Future<void> archiveCategory(int id) => _dao.archiveCategory(id);

  @override
  Future<void> unarchiveCategory(int id) => _dao.unarchiveCategory(id);

  @override
  Future<void> ensureSeeded() => _dao.ensureSeeded();
}
