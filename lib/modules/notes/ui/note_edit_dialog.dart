import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:worthtrack/data/db/app_database.dart';
import 'package:worthtrack/modules/notes/notes_providers.dart';

/// 打开笔记编辑器。[note] 为 null 表示新建。
Future<void> showNoteEditor(BuildContext context, {Note? note}) {
  return showDialog<void>(
    context: context,
    builder: (_) => NoteEditDialog(note: note),
  );
}

/// 新建 / 编辑笔记。
///
/// 刻意保持「两个输入框 + 保存」：记事本的价值是**记下来**，
/// 任何多一步的仪式感都会让人放弃记录。
class NoteEditDialog extends ConsumerStatefulWidget {
  const NoteEditDialog({super.key, this.note});

  final Note? note;

  @override
  ConsumerState<NoteEditDialog> createState() => _NoteEditDialogState();
}

class _NoteEditDialogState extends ConsumerState<NoteEditDialog> {
  late final TextEditingController _title = TextEditingController(
    text: widget.note?.title ?? '',
  );
  late final TextEditingController _body = TextEditingController(
    text: widget.note?.body ?? '',
  );
  bool _saving = false;

  bool get _isEditing => widget.note != null;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final title = _title.text.trim();
    final body = _body.text;
    if (title.isEmpty && body.trim().isEmpty) {
      _toast('空笔记就不存了');
      return;
    }

    setState(() => _saving = true);
    final repository = ref.read(noteRepositoryProvider);
    try {
      final note = widget.note;
      if (note == null) {
        await repository.createNote(title: title, body: body);
      } else {
        await repository.updateNote(id: note.id, title: title, body: body);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast('保存失败：$error');
    }
  }

  Future<void> _delete() async {
    final note = widget.note;
    if (note == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这条笔记？'),
        content: const Text('删除后无法恢复。'),
        actions: [
          TextButton(
            key: const Key('note-delete-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('note-delete-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await ref.read(noteRepositoryProvider).deleteNote(note.id);
    if (mounted) Navigator.of(context).pop();
  }

  void _toast(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEditing ? '编辑笔记' : '写一条'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('note-editor-title'),
                controller: _title,
                autofocus: true,
                textInputAction: TextInputAction.next,
                maxLength: 200,
                decoration: const InputDecoration(
                  labelText: '标题（可留空）',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('note-editor-body'),
                controller: _body,
                minLines: 4,
                maxLines: 12,
                keyboardType: TextInputType.multiline,
                decoration: const InputDecoration(
                  labelText: '正文',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (_isEditing)
          TextButton(
            key: const Key('note-editor-delete'),
            onPressed: _saving ? null : _delete,
            child: const Text('删除'),
          ),
        TextButton(
          key: const Key('note-editor-cancel'),
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('note-editor-save'),
          onPressed: _saving ? null : _save,
          child: const Text('保存'),
        ),
      ],
    );
  }
}
