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

  testWidgets('点图钉按钮切换置顶，走仓储的 setPinned', (tester) async {
    await pumpPage(
      tester,
      notes: [
        makeTestNote(1, title: '已置顶的', pinned: true),
        makeTestNote(2, title: '没置顶的'),
      ],
    );

    // 置顶的那条显示「取消置顶」，未置顶的显示「置顶」。
    await tester.tap(find.byKey(const Key('note-pin-2')));
    await tester.pumpAndSettle();

    expect(repo.pinnedCalls, [(id: 2, pinned: true)]);

    await tester.tap(find.byKey(const Key('note-pin-1')));
    await tester.pumpAndSettle();
    expect(repo.pinnedCalls.last, (id: 1, pinned: false));
  });

  group('搜索', () {
    Future<void> search(WidgetTester tester, String keyword) async {
      await tester.tap(find.byKey(const Key('notes-search-toggle')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('notes-search-field')),
        keyword,
      );
      await tester.pumpAndSettle();
    }

    testWidgets('按标题与正文过滤，命中的留下', (tester) async {
      await pumpPage(
        tester,
        notes: [
          makeTestNote(1, title: '买菜清单'),
          makeTestNote(2, title: '股票复盘', body: '顺便记一下买菜'),
          makeTestNote(3, title: '装修预算'),
        ],
      );

      await search(tester, '买菜');

      expect(find.byKey(const Key('note-tile-1')), findsOneWidget);
      expect(find.byKey(const Key('note-tile-2')), findsOneWidget);
      expect(find.byKey(const Key('note-tile-3')), findsNothing);
    });

    testWidgets('搜不到时给出「没有找到」而不是「一条都没有」', (tester) async {
      await pumpPage(tester, notes: [makeTestNote(1, title: '买菜清单')]);

      await search(tester, '股票');

      expect(find.text('没有找到「股票」'), findsOneWidget);
      expect(find.text('想到什么就写一条'), findsNothing);
    });

    testWidgets('关闭搜索后恢复全部，且清掉关键词', (tester) async {
      await pumpPage(
        tester,
        notes: [
          makeTestNote(1, title: '买菜清单'),
          makeTestNote(2, title: '股票复盘'),
        ],
      );

      await search(tester, '买菜');
      expect(find.byKey(const Key('note-tile-2')), findsNothing);

      await tester.tap(find.byKey(const Key('notes-search-toggle')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('note-tile-1')), findsOneWidget);
      expect(find.byKey(const Key('note-tile-2')), findsOneWidget);
      expect(find.byKey(const Key('notes-search-field')), findsNothing);
    });

    testWidgets('搜索时置顶仍排在最前（顺序不被过滤打乱）', (tester) async {
      await pumpPage(
        tester,
        notes: [
          makeTestNote(1, title: '置顶的买菜', pinned: true),
          makeTestNote(2, title: '后来的买菜'),
        ],
      );

      await search(tester, '买菜');

      final tiles = tester
          .widgetList<ListTile>(find.byType(ListTile))
          .map((tile) => (tile.key as ValueKey<String>).value)
          .toList();
      expect(tiles, ['note-tile-1', 'note-tile-2']);
    });
  });
}
