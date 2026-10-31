import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:worthtrack/data/db/app_database.dart';
import 'package:worthtrack/modules/notes/domain/note_ref.dart';
import 'package:worthtrack/modules/notes/notes_providers.dart';

/// 打开笔记编辑器。
///
/// [note] 为 null 表示新建；[noteRef] 非空表示这条笔记要挂到某个标的上
/// （从「相关笔记」页进来时自动带上）。
Future<void> showNoteEditor(
  BuildContext context, {
  Note? note,
  NoteRef? noteRef,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => NoteEditDialog(note: note, noteRef: noteRef),
  );
}

/// 新建 / 编辑笔记。
///
/// 刻意保持「两个输入框 + 保存」：记事本的价值是**记下来**，
/// 任何多一步的仪式感都会让人放弃记录。关联目标是随上下文带来的，
/// 不需要用户自己选。
class NoteEditDialog extends ConsumerStatefulWidget {
  const NoteEditDialog({super.key, this.note, this.noteRef});

  final Note? note;
  final NoteRef? noteRef;

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

  /// 当前要挂的弱引用目标：新建时来自上下文，编辑时来自已存的列。
  late NoteRef? _ref = widget.noteRef ?? _refOf(widget.note);

  /// 用户点了「解除关联」。单独记一个标记，而不是靠 `_ref == null` 判断，
  /// 否则「本来就没有关联」和「刚刚解除」会混成一种情况。
  bool _refDetached = false;

  bool get _isEditing => widget.note != null;

  static NoteRef? _refOf(Note? note) {
    final type = note?.refType;
    final id = note?.refId;
    if (type == null || type.isEmpty || id == null || id.isEmpty) return null;
    return NoteRef(type: type, id: id);
  }

  void _detachRef() {
    setState(() {
      _ref = null;
      _refDetached = true;
    });
  }

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
        await repository.createNote(
          title: title,
          body: body,
          refType: _ref?.type,
          refId: _ref?.id,
        );
      } else {
        await repository.updateNote(id: note.id, title: title, body: body);
        // 解除关联单独写一次：updateNote 只管标题与正文，
        // 免得「改个字」这种动作不小心把关联洗掉。
        if (_refDetached) await repository.setRef(note.id, null);
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
              if (_ref != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Chip(
                      key: const Key('note-editor-ref-chip'),
                      avatar: const Icon(Icons.link, size: 16),
                      label: Text('关联：${_ref!.display}'),
                      deleteIcon: const Icon(Icons.close, size: 16),
                      deleteButtonTooltipMessage: '解除关联',
                      onDeleted: _saving ? null : _detachRef,
                    ),
                  ),
                ),
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
