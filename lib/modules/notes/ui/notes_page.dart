import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:worthtrack/data/db/app_database.dart';
import 'package:worthtrack/modules/notes/domain/note_ref.dart';
import 'package:worthtrack/modules/notes/domain/note_text.dart';
import 'package:worthtrack/modules/notes/notes_providers.dart';
import 'package:worthtrack/modules/notes/ui/note_edit_dialog.dart';

/// 记事本列表页。
///
/// 排序规则由 DAO 决定（置顶在前 → 最近修改 → id 兜底），页面只负责展示，
/// 免得「排序逻辑」散落在 UI 与 SQL 两处、最后谁也不知道以谁为准。
///
/// 搜索在 Dart 端过滤（[noteMatchesKeyword]），不走 SQL `LIKE`——原因见该函数注释。
///
/// [noteRef] 非空时进入「相关笔记」模式：只列挂在该目标下的笔记。
/// 入口来自其他模块的路由跳转（如持仓页的「相关笔记」）——
/// 模块之间不 import，只传路径与查询参数。
class NotesPage extends ConsumerStatefulWidget {
  const NotesPage({super.key, this.noteRef});

  final NoteRef? noteRef;

  @override
  ConsumerState<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends ConsumerState<NotesPage> {
  final TextEditingController _search = TextEditingController();
  bool _searching = false;
  String _keyword = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) {
        _search.clear();
        _keyword = '';
      }
    });
  }

  void _pin(Note note) {
    // 置顶只写开关，不动 updatedAt（见 NoteRepository.setPinned）。
    ref.read(noteRepositoryProvider).setPinned(note.id, !note.pinned);
  }

  @override
  Widget build(BuildContext context) {
    final noteRef = widget.noteRef;
    final notes = noteRef == null
        ? ref.watch(notesProvider)
        : ref.watch(notesForRefProvider(noteRef));

    return Scaffold(
      appBar: AppBar(
        // 桌面端没有系统返回键，模块页必须自带回 launcher 的出口。
        leading: IconButton(
          key: const Key('notes-home'),
          tooltip: '返回首页',
          icon: const Icon(Icons.grid_view_rounded),
          onPressed: () => context.go('/'),
        ),
        title: _searching
            ? TextField(
                key: const Key('notes-search-field'),
                controller: _search,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  hintText: '搜索标题与正文',
                  border: InputBorder.none,
                ),
                onChanged: (value) => setState(() => _keyword = value),
              )
            : Text(noteRef == null ? '记事本' : '相关笔记'),
        actions: [
          IconButton(
            key: const Key('notes-search-toggle'),
            tooltip: _searching ? '关闭搜索' : '搜索',
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: _toggleSearch,
          ),
        ],
        bottom: noteRef == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(48),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16, bottom: 8),
                    child: Chip(
                      key: const Key('notes-ref-chip'),
                      avatar: const Icon(Icons.link, size: 16),
                      label: Text(noteRef.display),
                      deleteIcon: const Icon(Icons.close, size: 16),
                      deleteButtonTooltipMessage: '看全部笔记',
                      // 去掉筛选就是回本模块根路由，不需要另开页面。
                      onDeleted: () => context.go('/notes'),
                    ),
                  ),
                ),
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('notes-add'),
        // IndexedStack 里多个模块页面同时存活，默认 hero tag 会撞车。
        heroTag: 'notes-fab',
        onPressed: () => showNoteEditor(context, noteRef: noteRef),
        icon: const Icon(Icons.edit_outlined),
        label: const Text('写一条'),
      ),
      body: notes.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('读取失败：$error')),
        data: (all) {
          final list = [
            for (final note in all)
              if (noteMatchesKeyword(note.title, note.body, _keyword)) note,
          ];
          if (list.isEmpty) return _emptyState(noteRef);
          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 88),
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) =>
                _NoteTile(note: list[index], onPin: _pin),
          );
        },
      ),
    );
  }

  /// 「一条都没有」「搜不到」「这个标的还没有笔记」是三件不同的事，
  /// 共用一句文案会让用户以为笔记丢了。
  Widget _emptyState(NoteRef? noteRef) {
    final keyword = _keyword.trim();
    if (keyword.isNotEmpty) return _NoMatchState(keyword: keyword);
    if (noteRef != null) return _RefEmptyState(target: noteRef);
    return const _EmptyState();
  }
}

class _NoteTile extends StatelessWidget {
  const _NoteTile({required this.note, required this.onPin});

  final Note note;
  final void Function(Note note) onPin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      key: Key('note-tile-${note.id}'),
      leading: Icon(
        Icons.sticky_note_2_outlined,
        color: note.pinned
            ? theme.colorScheme.primary
            : theme.colorScheme.outline,
      ),
      title: Text(
        noteDisplayTitle(note.title, note.body),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(formatNoteTime(note.updatedAt)),
      trailing: IconButton(
        key: Key('note-pin-${note.id}'),
        tooltip: note.pinned ? '取消置顶' : '置顶',
        icon: Icon(note.pinned ? Icons.push_pin : Icons.push_pin_outlined),
        color: note.pinned
            ? theme.colorScheme.primary
            : theme.colorScheme.outline,
        onPressed: () => onPin(note),
      ),
      onTap: () => showNoteEditor(context, note: note),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return _CenteredHint(
      icon: Icons.sticky_note_2_outlined,
      title: '想到什么就写一条',
      subtitle: '不用起标题，也不用分类',
      color: Theme.of(context).colorScheme.outline,
    );
  }
}

class _RefEmptyState extends StatelessWidget {
  const _RefEmptyState({required this.target});

  final NoteRef target;

  @override
  Widget build(BuildContext context) {
    return _CenteredHint(
      icon: Icons.sticky_note_2_outlined,
      title: '还没有关于「${target.display}」的笔记',
      subtitle: '点右下角写一条，会自动关联',
      color: Theme.of(context).colorScheme.outline,
    );
  }
}

class _NoMatchState extends StatelessWidget {
  const _NoMatchState({required this.keyword});

  final String keyword;

  @override
  Widget build(BuildContext context) {
    return _CenteredHint(
      icon: Icons.search_off,
      title: '没有找到「$keyword」',
      subtitle: '换个词试试，搜索范围是标题和正文',
      color: Theme.of(context).colorScheme.outline,
    );
  }
}

class _CenteredHint extends StatelessWidget {
  const _CenteredHint({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 64),
      child: Column(
        children: [
          Icon(icon, size: 48, color: color),
          const SizedBox(height: 12),
          Text(title, style: theme.textTheme.bodyLarge),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}
