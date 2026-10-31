# Issues Backlog（待导入 GitHub Issues）

> 导入方式：拿到 classic token 后由 AI 一次性创建；或手工照抄。
> 每条 issue 的标签即里程碑分组（M1-M4）。

## M1 记账核心

### [M1] chore: WSL Ubuntu 24.04 Flutter 开发环境搭建
- 安装 Flutter SDK（stable）、JDK 17、Android SDK cmdline-tools + platform-tools、接受 licenses
- `flutter doctor` 全绿（除 iOS 项）；模拟器可用
- 环境搭建步骤文档化到 wiki 页面《WSL 开发环境》
- 验证：`flutter create` 冒烟项目在 WSL 内 build apk 成功

### [M1] feat: Flutter 项目脚手架初始化
- flutter create worthtrack（org com.zeekzhao.worthtrack），Android + linux/windows 桌面目标
- 接入 Riverpod、Drift、intl 依赖；目录骨架 lib/ui lib/repository lib/data
- 默认中文 locale；主题（Material 3，深浅色跟随系统）
- 验证：`flutter test` 冒烟测试通过

### [M1] ci: 验证 CI 三关在真实项目上跑通
- push 脚手架到 main，确认 format/analyze/test 三关执行且绿
- PR 分支验证 CI 状态检查生效（分支保护规则建议开启）

### [M1] feat: Drift 数据模型与 Migration 基建
- accounts / transactions / categories / budgets / recurring_rules / positions / price_cache 七张表
- 金额字段整数存「分」；Drift Migration 策略（schema 版本从 v1 起）
- Repository 层接口定义 + DAO 实现
- 单测：类型转换、金额分↔元、Migration 开库测试

### [M1] feat: 账户管理
- 账户 CRUD（现金/银行卡/信用卡/投资账户）、初始余额、余额实时计算（Drift Watch）
- Widget 测试：建账户主流程

### [M1] feat: 交易记录 CRUD 与流水列表
- 支出/收入/转账录入、编辑、删除（软删+冲销规则待定 issue 讨论）
- 流水列表按日分组、按账户/分类筛选、Drift 响应式刷新
- 单测：余额计算（记入/转出/跨账户转账）

### [M1] feat: 分类管理
- 收支分类 CRUD、图标选择、二级分类
- 预置默认分类集

### [M1] test: M1 集成测试（碰钱路径）
- 建账户 → 记支出 → 余额变化正确
- 两账户转账 → 双方余额正确
- 删除交易 → 余额回滚正确

## M2 报表与预算

### [M2] feat: 月度/年度报表
- 收支汇总、分类占比饼图、趋势折线（fl_chart）
- 单测：汇总/分组统计逻辑；Widget 测试：报表页渲染

### [M2] feat: 月度预算与超支提示
- 按分类设月度预算，进度条与超支提示
- 单测：预算消耗计算（含跨月边界）

### [M2] feat: 周期账单
- 规则 CRUD（日/周/月），应用启动时补生成漏掉的周期记账
- 单测：补生成逻辑（连续漏三期只生成三期不重复）——碰钱路径，必须全覆盖

### [M2] feat: 流水搜索与筛选
- 关键词/时间区间/账户/分类组合过滤

## M3 投资跟踪

### [M3] feat: 持仓管理
- 持仓 CRUD（代码/名称/份额/成本价），归属投资账户
- 单测：市值、盈亏、盈亏百分比计算

### [M3] feat: PriceProvider 行情接入（新浪/腾讯）
- 抽象 PriceProvider + TencentPriceProvider 实现；解析 A 股/场内基金报价
- 手动批量刷新入口；成功落 price_cache
- 单测：响应解析 fixture 测试（正常/停牌/代码不存在）
- 集成测试：刷新后市值更新（mock HTTP）

### [M3] feat: 行情缓存与手动改价兜底
- 拉取失败读缓存，UI 标注价格更新时间；持仓页支持手动改价
- 单测：缓存回退逻辑

### [M3] feat: 资产总览与净资产曲线
- 现金+储蓄+投资市值汇总、历史净资产曲线
- 单测：净资产聚合计算

### [M3] feat: 应用启动 PIN 锁
- local_auth/自实现 PIN，忘记 PIN 走重置（提示数据不丢）
- Widget 测试：锁屏解锁流程

## M4 备份与打磨

### [M4] feat: db 一键备份与恢复
- 导出 .db 到用户选择目录；恢复前强制二次确认
- 集成测试：备份→清空→恢复→数据一致

### [M4] feat: 交易流水 CSV 导出
- UTF-8 BOM；字段：时间/类型/账户/分类/金额/备注
- 单测：CSV 生成与中文转义

### [M4] ci: 发布流水线端到端验证
- 本地生成 keystore、配置 GitHub Secrets（KEYSTORE_BASE64 等）
- tag v0.1.0 试发布：Release 产物（签名 APK + Linux 包）可下载安装

### [M4] test: 碰钱路径集成测试补齐至清单全覆盖
- 对照 wiki《真机手测清单》与需求验收标准逐条核对

### [M4] docs: 用户手册与发版说明
- wiki 增加《真机手测清单》《用户手册》《WSL 开发环境》

---

## v2.0 模块化工具箱（M5-M8）

> 依据：wiki《需求规格-v2.0》与《模块化架构决策》（2026-10-31 grill-me 定稿）。
> 顺序不可调：M5 全部完成前不开 M6，否则是在移动的地基上盖房子。

## M5 模块化骨架（纯重构，零功能变化）

### [M5] refactor: 抽出 core 共享内核与 AppModule 契约 (#41)
- `lib/core/` 收纳 money / stream_utils / 通用组件；定义 `AppModule` 与 `ModuleContext`
- 契约字段：id / name / icon / defaultOrder / dependsOn / ownedTables / routes / settingsTiles / onEnable / onDisable / onClear
- 静态 `const modules = [...]` 注册表，不用 build_runner
- 模块禁止 import `di.dart`，只经 `ModuleContext` 取依赖

### [M5] refactor: finance 模块整体迁入 lib/modules/finance/ (#42)
- `git mv` 保留历史 → 改 import → format/analyze/test 三关全绿
- **验收：测试数与迁移前精确相等，提交内不得出现 `feat:`**

### [M5] feat: schema v2 —— module_state 表与首次 onUpgrade (#43)
- 本项目第一次写 migration：schemaVersion 1 → 2
- 迁移测试：造 v1 库 → 升级 → 逐表比对数据无损
- module_state：模块 id / 是否启用 / launcher 排序 / 首次启用时间（随备份走）

### [M5] feat: launcher 首页与 go_router 导航 (#44)
- `StatefulShellRoute.indexedStack`，每模块一个 branch，各自独立返回栈
- launcher：模块九宫格 + 常驻「记一笔 / 记一条」
- 冷启动恢复上次模块，30 分钟超时回 launcher
- 注意：这是对 `home_page.dart` 五个硬编码 tab 的破坏性重构

### [M5] feat: 模块管理页与设置页拆分 (#45)
- 启用 / 停用 / 清理数据 / 排序四个动作；停用与清理必须是两个独立入口
- 设置页拆成 core 系统设置（PIN / 备份恢复 / 模块管理）+ 各模块 `settingsTiles`
- **硬约束**：停用 finance 后仍能进入模块管理页重新启用（防死锁）

### [M5] test: 架构测试守住模块边界 (#46)
- 禁止跨模块直接访问他人表（按 `ownedTables` 校验）
- 禁止模块 import `di.dart` / 他人 DAO
- `ownedTables` 必须与 `@DriftDatabase(tables:)` 中的真实表一一对应

## M6 记事本

### [M6] feat: notes 表 + DAO + 仓储 (#47)
### [M6] feat: 记事本页（列表 / 编辑 / 置顶 / 搜索） (#48)
### [M6] feat: 弱引用（refType + refId，无外键）——从标的或账户跳到相关笔记 (#49)
### [M6] test: 模块停用/清理对 notes 数据的正确性 (#50)

## M7 关注与提醒

### [M7] feat: watchlist_items 表 + 自选列表（已有持仓自动并入，可单独隐藏） (#51)
### [M7] feat: 阈值提醒——目标价上穿/下穿、涨跌幅超 N%，前台轮询 + 应用内提醒条 (#52)
### [M7] test: 提醒去重（同一标的同一阈值当日只提醒一次）；断网时静默降级 (#53)

## M8 游戏与发版

### [M8] feat: game 模块——一个最小离线小游戏（无网络/无资源包/无内购） (#54)
### [M8] test: 新增模块成本验证——新增 game 只允许改注册表一行 + 新目录 (#55)
### [M8] docs: 用户手册与真机手测清单更新、v2.0.0 发版说明 (#56)
