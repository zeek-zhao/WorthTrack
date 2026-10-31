import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:worthtrack/data/db/app_database.dart';
import 'package:worthtrack/di.dart';
import 'package:worthtrack/modules/finance/ui/accounts/accounts_page.dart';
import 'package:worthtrack/modules/finance/ui/positions/positions_page.dart';
import 'package:worthtrack/modules/notes/domain/note_ref.dart';
import 'package:worthtrack/modules/notes/notes_providers.dart';
import 'package:worthtrack/modules/notes/ui/notes_page.dart';

import '../helpers/fake_account_repository.dart';
import '../helpers/fake_net_worth_repository.dart';
import '../helpers/fake_note_repository.dart';
import '../helpers/fake_position_repository.dart';

/// issue #49：跨模块「跳到相关笔记」的契约。
///
/// 模块之间禁止互相 import，所以「打开别人的页面」只能靠一条 URL。
/// 这个文件守的就是那条 URL：键名对不对、中文会不会乱码、
/// 笔记页能不能把它还原成筛选条件。
void main() {
  /// 首页放被测页面，`/notes` 只把收到的查询参数**解码后**回显出来。
  GoRouter echoRouter(Widget home) {
    return GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, __) => home),
        GoRoute(
          path: '/notes',
          builder: (context, state) {
            final query = state.uri.queryParameters;
            return Scaffold(
              body: Text(
                'NOTES ${query['refType']} ${query['refId']} ${query['refLabel']}',
              ),
            );
          },
        ),
      ],
    );
  }

  /// 真挂 NotesPage 的最小路由：`/` 是 launcher 桩，`/notes` 解析查询参数。
  GoRouter notesRouter(String initialLocation) {
    return GoRouter(
      initialLocation: initialLocation,
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(body: Text('LAUNCHER')),
        ),
        GoRoute(
          path: '/notes',
          builder: (context, state) =>
              NotesPage(noteRef: NoteRef.fromQuery(state.uri.queryParameters)),
        ),
      ],
    );
  }

  group('入口：从标的 / 账户跳到相关笔记', () {
    testWidgets('持仓页带上 refType=position 与标的代码、名称', (tester) async {
      final positions = FakePositionRepository();
      addTearDown(positions.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [positionRepositoryProvider.overrideWithValue(positions)],
          child: MaterialApp.router(
            routerConfig: echoRouter(const PositionsPage()),
          ),
        ),
      );
      positions.emit([makeTestPosition()]);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('position_menu_sh600519')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('position_notes_btn')));
      await tester.pumpAndSettle();

      // 中文标签经过 URL 编码再解码，回来必须还是原文。
      expect(find.text('NOTES position sh600519 贵州茅台'), findsOneWidget);
    });

    testWidgets('资产页带上 refType=account 与账户 id、名称', (tester) async {
      final accounts = FakeAccountRepository();
      final netWorth = FakeNetWorthRepository();
      addTearDown(accounts.dispose);
      addTearDown(netWorth.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            accountRepositoryProvider.overrideWithValue(accounts),
            netWorthRepositoryProvider.overrideWithValue(netWorth),
          ],
          child: MaterialApp.router(
            routerConfig: echoRouter(const AccountsPage()),
          ),
        ),
      );
      accounts.emit([makeTestAccount(3, '工资卡', AccountType.bank, 100000)]);
      netWorth.emit(makeTestOverview(cashMinor: 100000));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('account_notes_3')));
      await tester.pumpAndSettle();

      expect(find.text('NOTES account 3 工资卡'), findsOneWidget);
    });
  });

  group('落地：相关笔记页', () {
    const refQuery = '/notes?refType=position&refId=sh600519&refLabel=贵州茅台';

    late FakeNoteRepository repo;

    setUp(() => repo = FakeNoteRepository());
    tearDown(() => repo.dispose());

    Future<void> pumpNotes(
      WidgetTester tester, {
      required String location,
      List<Note>? notes,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [noteRepositoryProvider.overrideWithValue(repo)],
          child: MaterialApp.router(routerConfig: notesRouter(location)),
        ),
      );
      repo.emit(notes ?? const []);
      await tester.pumpAndSettle();
    }

    testWidgets('标题变「相关笔记」，chip 显示目标名，只列挂在该目标下的笔记', (tester) async {
      await pumpNotes(
        tester,
        location: refQuery,
        notes: [
          makeTestNote(
            1,
            title: '茅台的思考',
            refType: 'position',
            refId: 'sh600519',
          ),
          makeTestNote(2, title: '另一只', refType: 'position', refId: 'sz000001'),
          makeTestNote(3, title: '随手一条'),
        ],
      );

      expect(find.text('相关笔记'), findsOneWidget);
      expect(find.byKey(const Key('notes-ref-chip')), findsOneWidget);
      expect(find.text('贵州茅台'), findsOneWidget);

      expect(find.byKey(const Key('note-tile-1')), findsOneWidget);
      expect(find.byKey(const Key('note-tile-2')), findsNothing);
      expect(find.byKey(const Key('note-tile-3')), findsNothing);
    });

    testWidgets('该标的还没有笔记时，空态点名是谁', (tester) async {
      await pumpNotes(tester, location: refQuery);

      expect(find.text('还没有关于「贵州茅台」的笔记'), findsOneWidget);
      expect(find.text('想到什么就写一条'), findsNothing);
    });

    testWidgets('在这个页面写的一条，会自动挂上该目标', (tester) async {
      await pumpNotes(tester, location: refQuery);

      await tester.tap(find.byKey(const Key('notes-add')));
      await tester.pumpAndSettle();
      // 编辑器里能看到关联，不需要用户自己选。
      expect(find.text('关联：贵州茅台'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('note-editor-title')),
        '从这个页面写的',
      );
      await tester.tap(find.byKey(const Key('note-editor-save')));
      await tester.pumpAndSettle();

      expect(repo.created.single.refType, 'position');
      expect(repo.created.single.refId, 'sh600519');
    });

    testWidgets('点 chip 的 × 回到全部笔记', (tester) async {
      await pumpNotes(
        tester,
        location: refQuery,
        notes: [
          makeTestNote(1, title: '随手一条'),
          makeTestNote(
            2,
            title: '茅台的思考',
            refType: 'position',
            refId: 'sh600519',
          ),
        ],
      );
      expect(find.byKey(const Key('note-tile-1')), findsNothing);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.text('记事本'), findsOneWidget);
      expect(find.byKey(const Key('notes-ref-chip')), findsNothing);
      expect(find.byKey(const Key('note-tile-1')), findsOneWidget);
      expect(find.byKey(const Key('note-tile-2')), findsOneWidget);
    });

    testWidgets('左上角能回 launcher（桌面端没有系统返回键）', (tester) async {
      await pumpNotes(tester, location: refQuery);

      await tester.tap(find.byKey(const Key('notes-home')));
      await tester.pumpAndSettle();

      expect(find.text('LAUNCHER'), findsOneWidget);
    });
  });
}
