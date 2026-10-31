/// **装配入口**（composition root）：把所有 Provider 汇总到一个 import 点。
///
/// 分两层：
/// - `core/providers.dart`：数据库、PIN、备份、文件选择器——**core 服务**，
///   模块可以直接 import 它。
/// - `modules/finance/finance_providers.dart`：finance 自己的仓储——
///   只有 finance 内部与装配层知道它们。
///
/// 本文件只做 re-export，**不再定义任何 Provider**。这样模块不会 import 本文件
/// （避免为了一个仓储去依赖全部模块），页面与测试仍然可以只 import `di.dart`
/// 拿到全部注册（#45）。
library;

export 'package:worthtrack/core/providers.dart';
export 'package:worthtrack/modules/finance/finance_providers.dart';
