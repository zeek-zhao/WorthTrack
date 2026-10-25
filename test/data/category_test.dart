import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worthtrack/data/db/app_database.dart';

import '../helpers/sqlite3_loader.dart';

/// issue #7 验收：分类树操作单测。
void main() {
  setUpAll(setupSqlite3ForTests);

  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('分类树操作', () {
    test('新建一级/二级分类， parentId 关联正确', () async {
      final parentId = await db.categoryDao.createCategory(
        CategoriesCompanion.insert(name: '餐饮', kind: CategoryKind.expense),
      );
      final childId = await db.categoryDao.createCategory(
        CategoriesCompanion.insert(
          name: '早餐',
          kind: CategoryKind.expense,
          parentId: Value(parentId),
        ),
      );

      final child = await db.categoryDao.getById(childId);
      expect(child!.parentId, parentId);
      final parent = await db.categoryDao.getById(parentId);
      expect(parent!.parentId, isNull);
    });

    test('watchAll 默认过滤归档，恢复后回来', () async {
      final id = await db.categoryDao.createCategory(
        CategoriesCompanion.insert(name: '交通', kind: CategoryKind.expense),
      );
      await db.categoryDao.archiveCategory(id);
      expect((await db.categoryDao.watchAll().first).length, 0);
      await db.categoryDao.unarchiveCategory(id);
      expect((await db.categoryDao.watchAll().first).length, 1);
    });

    test('归档父分类级联归档子分类', () async {
      final parentId = await db.categoryDao.createCategory(
        CategoriesCompanion.insert(name: '娱乐', kind: CategoryKind.expense),
      );
      await db.categoryDao.createCategory(
        CategoriesCompanion.insert(
          name: '游戏',
          kind: CategoryKind.expense,
          parentId: Value(parentId),
        ),
      );

      await db.categoryDao.archiveCategory(parentId);

      final visible = await db.categoryDao.watchAll().first;
      expect(visible.where((c) => c.name == '娱乐'), isEmpty);
      expect(visible.where((c) => c.name == '游戏'), isEmpty);

      // 归档池里两笔都在（含归档查询）。
      final all = await db.categoryDao.watchAll(includeArchived: true).first;
      expect(
        all.where((c) => c.archivedAt != null).map((c) => c.name),
        containsAll(['娱乐', '游戏']),
      );
    });

    test('更新分类名称与图标', () async {
      final id = await db.categoryDao.createCategory(
        CategoriesCompanion.insert(name: '购物', kind: CategoryKind.expense),
      );
      await db.categoryDao.updateCategory(
        id,
        const CategoriesCompanion(name: Value('剁手'), icon: Value('🛍️')),
      );
      final updated = await db.categoryDao.getById(id);
      expect(updated!.name, '剁手');
      expect(updated.icon, '🛍️');
    });

    test('ensureSeeded 幂等：空表写入 12 个预置，重跑不重复', () async {
      await db.categoryDao.ensureSeeded();
      var all = await db.categoryDao.watchAll().first;
      expect(all.length, 12);
      expect(all.where((c) => c.kind == CategoryKind.expense).length, 8);
      expect(all.where((c) => c.kind == CategoryKind.income).length, 4);

      await db.categoryDao.ensureSeeded();
      all = await db.categoryDao.watchAll().first;
      expect(all.length, 12);
    });

    test('预置分类均为一级分类', () async {
      await db.categoryDao.ensureSeeded();
      final all = await db.categoryDao.watchAll().first;
      expect(all.every((c) => c.parentId == null), isTrue);
    });
  });
}
