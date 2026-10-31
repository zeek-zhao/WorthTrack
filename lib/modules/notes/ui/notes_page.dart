import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:worthtrack/data/db/app_database.dart';
import 'package:worthtrack/modules/notes/domain/note_text.dart';
import 'package:worthtrack/modules/notes/notes_providers.dart';
import 'package:worthtrack/modules/notes/ui/note_edit_dialog.dart';

/// 记事本列表页。
///
/// 排序规则由 DAO 决定（置顶在前 → 最近修改 → id 兜底），页面只负责展示，
/// 免得「排序逻辑」散落在 UI 与 SQL 两处、最后谁也不知道以谁为准。
///
/// 搜索在 Dart 端过滤（[noteMatchesKeyword]），不走 SQL `LIKE`——原因见该函数注释。
class NotesPage extends ConsumerStatefulWidget {
  const NotesPage({super.key});

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
    final notes = ref.watch(notesProvider);

    return Scaffold(
      appBar: AppBar(
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
            : const Text('记事本'),
        actions: [
          IconButton(
            key: const Key('notes-search-toggle'),
            tooltip: _searching ? '关闭搜索' : '搜索',
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: _toggleSearch,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('notes-add'),
        // IndexedStack 里多个模块页面同时存活，默认 hero tag 会撞车。
        heroTag: 'notes-fab',
        onPressed: () => showNoteEditor(context),
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
          if (list.isEmpty) {
            // 「一条笔记都没有」和「搜不到」是两件不同的事，
            // 用同一句空态文案会让用户以为笔记丢了。
            return _keyword.trim().isEmpty
                ? const _EmptyState()
                : _NoMatchState(keyword: _keyword.trim());
          }
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
    final theme = Theme.of(context);
    return _CenteredHint(
      icon: Icons.sticky_note_2_outlined,
      title: '想到什么就写一条',
      subtitle: '不用起标题，也不用分类',
      color: theme.colorScheme.outline,
    );
  }
}

class _NoMatchState extends StatelessWidget {
  const _NoMatchState({required this.keyword});

  final String keyword;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _CenteredHint(
      icon: Icons.search_off,
      title: '没有找到「$keyword」',
      subtitle: '换个词试试，搜索范围是标题和正文',
      color: theme.colorScheme.outline,
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
