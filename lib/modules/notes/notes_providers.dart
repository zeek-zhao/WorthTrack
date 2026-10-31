import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:worthtrack/core/providers.dart';
import 'package:worthtrack/data/db/app_database.dart';
import 'package:worthtrack/modules/notes/data/repositories/note_repository_impl.dart';
import 'package:worthtrack/modules/notes/domain/note_ref.dart';
import 'package:worthtrack/modules/notes/domain/repositories/note_repository.dart';

/// notes 模块的 Provider 注册点。
///
/// 和 finance 一样，模块自己的仓储放模块内，不进 `core/providers.dart`：
/// 否则 core 会反向依赖 notes，模块化就白做了。
final noteRepositoryProvider = Provider<NoteRepository>((ref) {
  return NoteRepositoryImpl(ref.watch(appDatabaseProvider).noteDao);
});

/// 笔记列表流（置顶在前，同组按最近修改倒序）。
final notesProvider = StreamProvider<List<Note>>((ref) {
  return ref.watch(noteRepositoryProvider).watchNotes();
});

/// 挂在某个弱引用目标下的笔记流（同一套排序）。
///
/// 用 family 而不是把 ref 塞进页面状态：目标一变就该换一条流，
/// 让 Riverpod 负责销毁旧订阅，页面不必自己管。
final notesForRefProvider = StreamProvider.family<List<Note>, NoteRef>((
  ref,
  target,
) {
  return ref
      .watch(noteRepositoryProvider)
      .watchNotesForRef(refType: target.type, refId: target.id);
});
