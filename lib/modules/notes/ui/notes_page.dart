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
class NotesPage extends ConsumerWidget {
  const NotesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notes = ref.watch(notesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('记事本')),
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
        data: (list) => list.isEmpty
            ? const _EmptyState()
            : ListView.separated(
                padding: const EdgeInsets.only(bottom: 88),
                itemCount: list.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) => _NoteTile(note: list[index]),
              ),
      ),
    );
  }
}

class _NoteTile extends StatelessWidget {
  const _NoteTile({required this.note});

  final Note note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      key: Key('note-tile-${note.id}'),
      leading: Icon(
        note.pinned ? Icons.push_pin : Icons.sticky_note_2_outlined,
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
      onTap: () => showNoteEditor(context, note: note),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 64),
      child: Column(
        children: [
          Icon(
            Icons.sticky_note_2_outlined,
            size: 48,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text('想到什么就写一条', style: theme.textTheme.bodyLarge),
          const SizedBox(height: 4),
          Text(
            '不用起标题，也不用分类',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}
