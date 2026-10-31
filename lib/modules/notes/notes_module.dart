import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:worthtrack/core/module/app_module.dart';
import 'package:worthtrack/modules/notes/domain/note_ref.dart';
import 'package:worthtrack/modules/notes/ui/note_edit_dialog.dart';
import 'package:worthtrack/modules/notes/ui/notes_page.dart';

/// notes 模块：记事本。
///
/// v2.0 的第一个**新增**模块，它的存在同时是一个成本验证：
/// 新增模块 = 加一个目录 + 注册表里加一行（issue #55 会量化这一点）。
///
/// ## 跨模块契约
///
/// 别的模块想打开「某标的 / 某账户的相关笔记」时，**不 import 本模块**，
/// 只跳一条路由：
///
/// ```dart
/// context.go(moduleRoute('notes', query: {
///   'refType': 'position',   // position / account
///   'refId': 'sh600519',     // 证券代码，或账户 id 的字符串
///   'refLabel': '贵州茅台',   // 可选，纯展示
/// }));
/// ```
///
/// 查询参数就是契约本身：`refType` / `refId` 决定筛选，`refLabel` 只是好看。
/// 少了 `refType` 或 `refId` 就退化成全部笔记，不会报错。
class NotesModule extends AppModule {
  const NotesModule();

  @override
  ModuleId get id => 'notes';

  @override
  String get name => '记事本';

  @override
  IconData get icon => Icons.sticky_note_2_outlined;

  /// finance 是 10，这里 20：记账是主功能，记事本是随手记。
  @override
  int get defaultOrder => 20;

  /// 与 `@DriftDatabase(tables: [...])` 里的真实表一一对应（架构测试会校验）。
  @override
  Set<String> get ownedTables => const {'notes'};

  @override
  Map<String, String> get tableLabels => const {'notes': '笔记'};

  @override
  List<RouteBase> get routes => [
    GoRoute(
      path: '/notes',
      builder: (context, state) =>
          NotesPage(noteRef: NoteRef.fromQuery(state.uri.queryParameters)),
    ),
  ];

  /// 「写一条」常驻快捷：想到的事不该先点进模块再点加号，**1 步**才留得住。
  @override
  List<Widget> quickActions(BuildContext context) => [
    Builder(
      builder: (context) => FilledButton.tonalIcon(
        onPressed: () => showNoteEditor(context),
        icon: const Icon(Icons.edit_outlined),
        label: const Text('写一条'),
      ),
    ),
  ];
}
