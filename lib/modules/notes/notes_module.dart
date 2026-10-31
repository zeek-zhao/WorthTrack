import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:worthtrack/core/module/app_module.dart';
import 'package:worthtrack/modules/notes/ui/note_edit_dialog.dart';
import 'package:worthtrack/modules/notes/ui/notes_page.dart';

/// notes 模块：记事本。
///
/// v2.0 的第一个**新增**模块，它的存在同时是一个成本验证：
/// 新增模块 = 加一个目录 + 注册表里加一行（issue #55 会量化这一点）。
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
    GoRoute(path: '/notes', builder: (context, state) => const NotesPage()),
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
