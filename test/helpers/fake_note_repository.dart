import 'dart:async';

import 'package:worthtrack/data/db/app_database.dart';
import 'package:worthtrack/modules/notes/domain/repositories/note_repository.dart';

import 'fake_transaction_repository.dart' show replayStream;

/// 内存假实现：驱动记事本 UI 测试，不依赖数据库。
class FakeNoteRepository implements NoteRepository {
  final _controller = StreamController<List<Note>>.broadcast();
  List<Note> _notes = [];
  int _nextId = 1;

  /// 记录「新建时传了什么」，供断言 UI 是否真的把内容交了出去。
  final List<({String title, String body})> created = [];

  /// 记录被删的 id。
  final List<int> deleted = [];

  /// 记录置顶调用。
  final List<({int id, bool pinned})> pinnedCalls = [];

  void emit(List<Note> notes) {
    _notes = notes;
    _controller.add(notes);
  }

  @override
  Stream<List<Note>> watchNotes() => replayStream(_notes, _controller);

  @override
  Future<Note?> getById(int id) async {
    for (final note in _notes) {
      if (note.id == id) return note;
    }
    return null;
  }

  @override
  Future<int> createNote({
    required String title,
    required String body,
    String? refType,
    String? refId,
  }) async {
    created.add((title: title, body: body));
    final id = _nextId++;
    emit([makeTestNote(id, title: title, body: body), ..._notes]);
    return id;
  }

  @override
  Future<void> updateNote({
    required int id,
    required String title,
    required String body,
  }) async {
    emit([
      for (final note in _notes)
        if (note.id == id) makeTestNote(id, title: title, body: body) else note,
    ]);
  }

  @override
  Future<void> setPinned(int id, bool pinned) async {
    pinnedCalls.add((id: id, pinned: pinned));
  }

  @override
  Future<void> deleteNote(int id) async {
    deleted.add(id);
    emit([
      for (final note in _notes)
        if (note.id != id) note,
    ]);
  }

  void dispose() => _controller.close();
}

/// 构造测试用笔记行。
Note makeTestNote(
  int id, {
  String title = '',
  String body = '',
  bool pinned = false,
  DateTime? updatedAt,
}) => Note(
  id: id,
  title: title,
  body: body,
  pinned: pinned,
  refType: null,
  refId: null,
  createdAt: DateTime(2026, 10, 31, 9),
  updatedAt: updatedAt ?? DateTime(2026, 10, 31, 9),
);
