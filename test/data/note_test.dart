import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worthtrack/data/db/app_database.dart';
import 'package:worthtrack/modules/notes/data/repositories/note_repository_impl.dart';
import 'package:worthtrack/modules/notes/domain/note_ref.dart';
import 'package:worthtrack/modules/notes/domain/repositories/note_repository.dart';

import '../helpers/sqlite3_loader.dart';

/// issue #47：notes 表 + DAO + 仓储。
///
/// 用真 Drift 内存库跑，不打桩——排序、默认值、约束这些正是「打桩会测不到」的部分。
void main() {
  setUpAll(setupSqlite3ForTests);

  late AppDatabase db;
  late NoteRepository repo;
  var now = DateTime(2026, 10, 31, 9);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    now = DateTime(2026, 10, 31, 9);
    repo = NoteRepositoryImpl(db.noteDao, now: () => now);
  });

  tearDown(() async {
    await db.close();
  });

  /// 建一条笔记并把时间往后推 1 分钟，保证「后写的更新」。
  Future<int> addNote(
    String title, {
    String body = '',
    String? refType,
    String? refId,
  }) async {
    final id = await repo.createNote(
      title: title,
      body: body,
      refType: refType,
      refId: refId,
    );
    now = now.add(const Duration(minutes: 1));
    return id;
  }

  group('创建与读取', () {
    test('新建笔记：createdAt 与 updatedAt 同一次写入，置顶默认 false', () async {
      final at = DateTime(2026, 10, 31, 9, 30);
      now = at;
      final id = await repo.createNote(title: '午饭想法', body: '少吃点');

      final note = await repo.getById(id);
      expect(note, isNotNull);
      expect(note!.title, '午饭想法');
      expect(note.body, '少吃点');
      expect(note.pinned, isFalse);
      expect(note.createdAt, at);
      expect(note.updatedAt, at);
    });

    test('标题可以为空：随手记一句不该被表单拦住', () async {
      final id = await repo.createNote(title: '', body: '只写正文');
      expect((await repo.getById(id))!.title, isEmpty);
    });

    test('不存在的 id 返回 null', () async {
      expect(await repo.getById(9999), isNull);
    });

    test('弱引用落库：refType + refId 是纯字符串，可为空', () async {
      final linked = await addNote(
        '茅台的思考',
        refType: 'position',
        refId: 'sh600519',
      );
      final plain = await addNote('随手一条');

      final a = await repo.getById(linked);
      expect(a!.refType, 'position');
      expect(a.refId, 'sh600519');

      final b = await repo.getById(plain);
      expect(b!.refType, isNull);
      expect(b.refId, isNull);
    });
  });

  group('列表顺序', () {
    test('置顶恒在前，同组按最近修改倒序，最后按 id 兜底', () async {
      final first = await addNote('第一条');
      final second = await addNote('第二条');
      final third = await addNote('第三条');

      // 置顶最早那条：它必须跳到最前，但组内仍按时间排。
      await repo.setPinned(first, true);

      final list = await repo.watchNotes().first;
      expect(list.map((n) => n.id).toList(), [first, third, second]);

      // 取消置顶后回到纯时间序。
      await repo.setPinned(first, false);
      final after = await repo.watchNotes().first;
      expect(after.map((n) => n.id).toList(), [third, second, first]);
    });

    test('同一时间写入的多条按 id 倒序（保证次序稳定不跳位）', () async {
      // 不推进时间：三条的 updatedAt 完全相同。
      final a = await repo.createNote(title: 'a', body: '');
      final b = await repo.createNote(title: 'b', body: '');
      final c = await repo.createNote(title: 'c', body: '');

      final list = await repo.watchNotes().first;
      expect(list.map((n) => n.id).toList(), [c, b, a]);
    });
  });

  group('更新与置顶', () {
    test('更新标题正文会把 updatedAt 推到当前时间，createdAt 不动', () async {
      final id = await addNote('旧标题', body: '旧正文');
      final createdAt = (await repo.getById(id))!.createdAt;

      final updatedAt = now.add(const Duration(hours: 2));
      now = updatedAt;
      await repo.updateNote(id: id, title: '新标题', body: '新正文');

      final note = await repo.getById(id);
      expect(note!.title, '新标题');
      expect(note.body, '新正文');
      expect(note.updatedAt, updatedAt);
      expect(note.createdAt, createdAt);
    });

    test('置顶不修改 updatedAt：视图偏好不该打乱「最近改过」', () async {
      final id = await addNote('一条笔记');
      final before = (await repo.getById(id))!.updatedAt;

      now = now.add(const Duration(days: 3));
      await repo.setPinned(id, true);

      final note = await repo.getById(id);
      expect(note!.pinned, isTrue);
      expect(note.updatedAt, before);
    });
  });

  group('删除', () {
    test('删除是硬删除，列表里不再出现', () async {
      final keep = await addNote('留着');
      final gone = await addNote('删掉');

      await repo.deleteNote(gone);

      final list = await repo.watchNotes().first;
      expect(list.map((n) => n.id).toList(), [keep]);
      expect(await repo.getById(gone), isNull);
    });

    test('删不存在的 id 不抛异常（重复点击不该炸）', () async {
      await repo.deleteNote(424242);
    });
  });

  group('弱引用（#49）', () {
    test('按 refType + refId 取笔记，别人的不会混进来', () async {
      await addNote('茅台的思考', refType: 'position', refId: 'sh600519');
      await addNote('另一个标的', refType: 'position', refId: 'sz000001');
      await addNote('工资卡的备注', refType: 'account', refId: '1');
      await addNote('什么都没挂');

      final forMoutai = await repo
          .watchNotesForRef(refType: 'position', refId: 'sh600519')
          .first;
      expect(forMoutai.map((n) => n.title), ['茅台的思考']);

      final forAccount = await repo
          .watchNotesForRef(refType: 'account', refId: '1')
          .first;
      expect(forAccount.map((n) => n.title), ['工资卡的备注']);
    });

    test('同一个 id 不同类型的不会互相串（position:1 vs account:1）', () async {
      await addNote('标的 1', refType: 'position', refId: '1');
      await addNote('账户 1', refType: 'account', refId: '1');

      final byPosition = await repo
          .watchNotesForRef(refType: 'position', refId: '1')
          .first;
      expect(byPosition.map((n) => n.title), ['标的 1']);
    });

    test('相关笔记沿用同一套排序（置顶 → 最近修改）', () async {
      final first = await addNote(
        '先记的',
        refType: 'position',
        refId: 'sh600519',
      );
      await addNote('后记的', refType: 'position', refId: 'sh600519');

      await repo.setPinned(first, true);
      final list = await repo
          .watchNotesForRef(refType: 'position', refId: 'sh600519')
          .first;
      expect(list.map((n) => n.title), ['先记的', '后记的']);
    });

    test('setRef 改绑会推 updatedAt（关联属于内容）', () async {
      final id = await addNote('一条笔记');
      final before = (await repo.getById(id))!.updatedAt;

      final at = now.add(const Duration(hours: 1));
      now = at;
      await repo.setRef(id, const NoteRef(type: 'account', id: '7'));

      final note = await repo.getById(id);
      expect(note!.refType, 'account');
      expect(note.refId, '7');
      expect(note.updatedAt, at);
      expect(note.updatedAt, isNot(before));
    });

    test('setRef 传 null 解除关联，两列一起清空', () async {
      final id = await addNote(
        '挂了标的的笔记',
        refType: 'position',
        refId: 'sh600519',
      );

      await repo.setRef(id, null);

      final note = await repo.getById(id);
      expect(note!.refType, isNull);
      expect(note.refId, isNull);
    });
  });
}
