import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worthtrack/data/db/app_database.dart';
import 'package:worthtrack/modules/notes/notes_providers.dart';
import 'package:worthtrack/modules/notes/ui/notes_page.dart';

import '../helpers/fake_note_repository.dart';

/// issue #47：记事本列表页与编辑器的最小闭环。
void main() {
  late FakeNoteRepository repo;

  setUp(() => repo = FakeNoteRepository());
  tearDown(() => repo.dispose());

  Future<void> pumpPage(WidgetTester tester, {List<Note>? notes}) async {
    if (notes != null) repo.emit(notes);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [noteRepositoryProvider.overrideWithValue(repo)],
        child: const MaterialApp(home: NotesPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('空态：不催用户分类，只鼓励写下来', (tester) async {
    await pumpPage(tester);

    expect(find.text('想到什么就写一条'), findsOneWidget);
    expect(find.byKey(const Key('notes-add')), findsOneWidget);
  });

  testWidgets('列表按仓储给的顺序渲染，置顶那条带图钉', (tester) async {
    await pumpPage(
      tester,
      notes: [
        makeTestNote(1, title: '置顶的', pinned: true),
        makeTestNote(2, title: '普通的'),
      ],
    );

    expect(find.byKey(const Key('note-tile-1')), findsOneWidget);
    expect(find.byKey(const Key('note-tile-2')), findsOneWidget);
    expect(find.text('置顶的'), findsOneWidget);
    expect(find.text('普通的'), findsOneWidget);
    expect(find.byIcon(Icons.push_pin), findsOneWidget);
  });

  testWidgets('没写标题的笔记，列表里显示正文首行', (tester) async {
    await pumpPage(tester, notes: [makeTestNote(1, body: '只写了正文\n第二行')]);

    expect(find.text('只写了正文'), findsOneWidget);
  });

  testWidgets('点「写一条」→ 输入 → 保存，内容真的交给了仓储', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.byKey(const Key('notes-add')));
    await tester.pumpAndSettle();
    expect(find.text('写一条'), findsWidgets);

    await tester.enterText(find.byKey(const Key('note-editor-title')), '下午的想法');
    await tester.enterText(
      find.byKey(const Key('note-editor-body')),
      '把 M6 的坑记一下',
    );
    await tester.tap(find.byKey(const Key('note-editor-save')));
    await tester.pumpAndSettle();

    expect(repo.created, hasLength(1));
    expect(repo.created.single.title, '下午的想法');
    expect(repo.created.single.body, '把 M6 的坑记一下');
    // 保存后对话框关闭，列表里能看到新笔记。
    expect(find.text('下午的想法'), findsOneWidget);
  });

  testWidgets('标题与正文都空时不写库，只提示', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.byKey(const Key('notes-add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('note-editor-save')));
    await tester.pumpAndSettle();

    expect(repo.created, isEmpty);
    expect(find.text('空笔记就不存了'), findsOneWidget);
  });

  testWidgets('编辑已有笔记：点条目打开，改完写回', (tester) async {
    await pumpPage(tester, notes: [makeTestNote(7, title: '旧标题')]);

    await tester.tap(find.byKey(const Key('note-tile-7')));
    await tester.pumpAndSettle();
    expect(find.text('编辑笔记'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('note-editor-title')), '新标题');
    await tester.tap(find.byKey(const Key('note-editor-save')));
    await tester.pumpAndSettle();

    expect(find.text('新标题'), findsOneWidget);
    expect(find.text('旧标题'), findsNothing);
  });
}
