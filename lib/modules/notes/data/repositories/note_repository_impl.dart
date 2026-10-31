import 'package:drift/drift.dart';

import 'package:worthtrack/data/db/app_database.dart';
import 'package:worthtrack/modules/notes/data/dao/note_dao.dart';
import 'package:worthtrack/modules/notes/domain/note_ref.dart';
import 'package:worthtrack/modules/notes/domain/repositories/note_repository.dart';

/// [NoteRepository] 的 Drift 实现。
class NoteRepositoryImpl implements NoteRepository {
  /// [now] 可注入，测试里用来固定时间（排序与 `updatedAt` 断言都依赖它）。
  NoteRepositoryImpl(this._dao, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final NoteDao _dao;
  final DateTime Function() _now;

  @override
  Stream<List<Note>> watchNotes() => _dao.watchNotes();

  @override
  Stream<List<Note>> watchNotesForRef({
    required String refType,
    required String refId,
  }) {
    return _dao.watchNotesForRef(refType: refType, refId: refId);
  }

  @override
  Future<Note?> getById(int id) => _dao.getById(id);

  @override
  Future<int> createNote({
    required String title,
    required String body,
    String? refType,
    String? refId,
  }) {
    final at = _now();
    return _dao.createNote(
      NotesCompanion.insert(
        title: title,
        body: Value(body),
        refType: Value(refType),
        refId: Value(refId),
        createdAt: Value(at),
        updatedAt: Value(at),
      ),
    );
  }

  @override
  Future<void> updateNote({
    required int id,
    required String title,
    required String body,
  }) {
    return _dao.updateNote(
      id,
      NotesCompanion(
        title: Value(title),
        body: Value(body),
        updatedAt: Value(_now()),
      ),
    );
  }

  @override
  Future<void> setPinned(int id, bool pinned) => _dao.setPinned(id, pinned);

  @override
  Future<void> setRef(int id, NoteRef? ref) {
    return _dao.setRef(id, ref?.type, ref?.id, _now());
  }

  @override
  Future<void> deleteNote(int id) => _dao.deleteNote(id);
}
