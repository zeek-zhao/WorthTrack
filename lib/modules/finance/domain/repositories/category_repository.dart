import 'package:worthtrack/data/db/app_database.dart';

/// 分类领域接口。
abstract class CategoryRepository {
  /// 监听使用中的分类（不含归档）。
  Stream<List<Category>> watchAll();

  /// 按 id 查询，不存在返回 null。
  Future<Category?> getById(int id);

  /// 新建分类。parentId 非空时为二级分类（父分类必须为一级）。
  Future<int> createCategory({
    required String name,
    required CategoryKind kind,
    String? icon,
    int? parentId,
    int sortOrder = 0,
  });

  /// 更新分类（名称/图标/排序）。
  Future<void> updateCategory({
    required int id,
    String? name,
    String? icon,
    int? sortOrder,
  });

  /// 归档分类（级联归档子分类）。
  Future<void> archiveCategory(int id);

  /// 恢复分类。
  Future<void> unarchiveCategory(int id);

  /// 预置分类 seed（幂等）。
  Future<void> ensureSeeded();
}
