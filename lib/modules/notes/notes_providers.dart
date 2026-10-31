import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:worthtrack/core/providers.dart';
import 'package:worthtrack/data/db/app_database.dart';
import 'package:worthtrack/modules/notes/data/repositories/note_repository_impl.dart';
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
