/// 笔记的弱引用目标（某个标的、某个账户……）。
///
/// **只存字符串，不建外键**：被引用方被删、或所属模块被停用清理时，
/// 这里只会变成一条悬空字符串，不会破坏任何完整性约束。
/// 这是 v2.0 对跨模块关联的硬约束（wiki §4）。
///
/// [label] 只用于展示（如「贵州茅台」），**不入库**：它是引用方那一侧的知识，
/// 存进笔记里会过期，而且会让笔记表开始依赖别的模块的字段。
class NoteRef {
  const NoteRef({required this.type, required this.id, this.label});

  /// 被引用对象的类型：`position`（标的）/ `account`（账户）。
  final String type;

  /// 被引用对象的标识：证券代码 `sh600519`、账户 id 的字符串形式。
  final String id;

  /// 展示名，可为空（为空时直接显示 [id]）。
  final String? label;

  /// 从路由查询参数还原；缺 `refType` 或 `refId` 时返回 null。
  static NoteRef? fromQuery(Map<String, String> query) {
    final type = query['refType'];
    final id = query['refId'];
    if (type == null || type.isEmpty || id == null || id.isEmpty) return null;
    final label = query['refLabel'];
    return NoteRef(
      type: type,
      id: id,
      label: (label == null || label.isEmpty) ? null : label,
    );
  }

  /// 转成路由查询参数（跳转用）。
  Map<String, String> toQuery() => {
    'refType': type,
    'refId': id,
    if (label != null && label!.isNotEmpty) 'refLabel': label!,
  };

  /// 列表/确认框里显示什么。
  String get display => (label == null || label!.isEmpty) ? id : label!;

  @override
  bool operator ==(Object other) =>
      other is NoteRef &&
      other.type == type &&
      other.id == id &&
      other.label == label;

  @override
  int get hashCode => Object.hash(type, id, label);

  @override
  String toString() => 'NoteRef($type:$id${label == null ? '' : ' $label'})';
}
