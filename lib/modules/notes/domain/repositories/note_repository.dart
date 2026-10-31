import 'package:worthtrack/data/db/app_database.dart';
import 'package:worthtrack/modules/notes/domain/note_ref.dart';

/// 笔记领域接口：UI 层只依赖此抽象，不直接触碰 Drift。
///
/// 只暴露「记事本需要什么」，不暴露 Drift 的 Companion / 表达式——
/// 将来换存储（比如换成文件）时，改的只是这个接口的实现。
abstract class NoteRepository {
  /// 监听全部笔记（置顶在前，同组按最近修改倒序）。
  Stream<List<Note>> watchNotes();

  /// 监听挂在某个弱引用目标下的笔记（同一套排序规则）。
  Stream<List<Note>> watchNotesForRef({
    required String refType,
    required String refId,
  });

  /// 按 id 查询，不存在返回 null。
  Future<Note?> getById(int id);

  /// 新建笔记，返回 id。
  ///
  /// [refType] / [refId] 是**弱引用**：只存字符串，不建外键（#49）。
  Future<int> createNote({
    required String title,
    required String body,
    String? refType,
    String? refId,
  });

  /// 更新标题与正文，同时把 `updatedAt` 推到当前时间。
  Future<void> updateNote({
    required int id,
    required String title,
    required String body,
  });

  /// 置顶 / 取消置顶。**不动 `updatedAt`**：置顶是视图偏好，不是内容修改，
  /// 否则「最近改过的排前面」会被一次置顶操作打乱。
  Future<void> setPinned(int id, bool pinned);

  /// 改绑 / 解除弱引用（传 `null` 表示解除）。
  ///
  /// 与置顶不同，这一列属于内容，所以要推 `updatedAt`。
  Future<void> setRef(int id, NoteRef? ref);

  /// 删除笔记（硬删除，笔记没有「归档」概念）。
  Future<void> deleteNote(int id);
}
