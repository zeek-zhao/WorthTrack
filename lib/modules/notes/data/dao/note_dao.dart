import 'package:drift/drift.dart';

import 'package:worthtrack/data/db/app_database.dart';

part 'note_dao.g.dart';

/// 笔记表 DAO（notes 模块自有）。
///
/// 只碰 `notes` 一张表——这条边界由 `test/architecture/` 扫描守着，
/// 不靠自觉。
@DriftAccessor(tables: [Notes])
class NoteDao extends DatabaseAccessor<AppDatabase> with _$NoteDaoMixin {
  NoteDao(super.db);

  /// 监听全部笔记：**置顶恒在前**，同组内按最近修改倒序，最后按 id 兜底。
  ///
  /// 加 id 兜底是因为 `updatedAt` 可能撞在同一秒（批量导入、快速连写），
  /// 没有稳定次序时列表会在两次刷新之间跳位。
  Stream<List<Note>> watchNotes() {
    return (select(notes)..orderBy([
          (n) => OrderingTerm.desc(n.pinned),
          (n) => OrderingTerm.desc(n.updatedAt),
          (n) => OrderingTerm.desc(n.id),
        ]))
        .watch();
  }

  Future<Note?> getById(int id) {
    return (select(notes)..where((n) => n.id.equals(id))).getSingleOrNull();
  }

  Future<int> createNote(NotesCompanion entry) {
    return into(notes).insert(entry);
  }

  /// 更新标题/正文（`updatedAt` 由调用方写入，DAO 不擅自改时间）。
  Future<void> updateNote(int id, NotesCompanion entry) {
    return (update(notes)..where((n) => n.id.equals(id))).write(entry);
  }

  Future<void> setPinned(int id, bool pinned) {
    return (update(notes)..where((n) => n.id.equals(id))).write(
      NotesCompanion(pinned: Value(pinned)),
    );
  }

  Future<void> deleteNote(int id) {
    return (delete(notes)..where((n) => n.id.equals(id))).go();
  }
}
