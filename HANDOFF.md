# WorthTrack 交接文档（给接手的 AI）

> 生成时间：2026-10-31 ｜ 交接点：**v1.0.0 已发布，v2.0 的 M5（模块化改造）已合入 main，下一步 M6 记事本**
> 读这一份即可接手，不需要回溯历史对话。更细的历史坑见 `docs/troubleshooting.md`，改动流水见 `docs/ai-changelog.md`。

---

## 0. 一句话现状

`main = 7663ae0`（M5 收口 PR #65 + M6 第一条 PR #66），M5 六条 **6/6 全部完成**；
**M6 记事本进度 1/4**：#47（`notes` 表 + DAO + 仓储 + 模块注册）已完成，测试基线 **478**。
下一步 **#48 记事本页**（置顶 / 搜索 / 排序打磨；列表与编辑已在 #47 落地）。
⚠️ v2.0 代码尚未真机手测，M8 发版前按手测清单走一遍（v1.0.0 已手测通过）。

---

## 1. 先做这四件事（验证环境）

```bash
cd /d/zeek/WorkBuddy/WorthTrack
git log --oneline -3                                  # 应为 #44 的提交起
bash scripts/wt_flutter.sh flutter --version          # 应为 3.35.4 / Dart 3.9.2
bash scripts/wt_flutter.sh flutter test --reporter compact   # 应为 478 个全绿
```

> **所有 flutter / dart 命令必须走 `bash scripts/wt_flutter.sh`**，直接调会因 WSL 的 PATH 与引号污染失败。
> 所有 `wsl.exe` 调用必须加 `MSYS_NO_PATHCONV=1`，否则 `/mnt/...` 会被 MSYS 改写。

---

## 2. 项目是什么

**WorthTrack**：Flutter 跨平台、纯本地的个人工具。
仓库 https://github.com/zeek-zhao/WorthTrack （public），Android 手机优先，桌面（Linux/Windows）跑同款布局。

- **v1.0（已发布能力）**：手工记账（多账户/分类/预算/周期账单/报表）+ A股与场内基金持仓跟踪（腾讯行情、缓存价兜底、手动改价）+ 净资产曲线 + 整库备份恢复 + CSV 导出 + PIN 锁
- **v2.0（已定稿、待实现）**：从「记账应用」升级为「**本地优先的个人工具箱**」，4 个可开关模块：
  `finance`（记账与资产，已有）｜ `watchlist`（自选与阈值提醒，新建）｜ `notes`（记事本，新建）｜ `game`（一个最小离线小游戏，新建）

技术栈：Flutter 3.35.4 + Riverpod 3 + Drift(SQLite)。金额一律**整数分**，份额整数**0.01 份**。

---

## 3. 代码地图

```
lib/
  main.dart / app.dart          # 入口、主题（Material 3，跟随系统深浅色）
  di.dart                       # ⚠️ 装配入口，**只做 re-export**（core/providers + 各模块 providers）
  core/                         # 共享内核（core 级，不属任何模块）
    providers.dart              #   ⚠️ core 服务注册：数据库 / PIN / 备份 / 文件选择器
    money.dart                  #   分↔元转换
    stream_utils.dart           #   combineLatest2/3，组合多个 drift watch 流
    module/app_module.dart      #   ⚠️ AppModule 契约 + ModuleContext + ModuleLogger（#41/#44/#45）
    module/module_registry.dart #   ⚠️ appModules 注册表 + validateModuleRegistry + orderModules（#41/#45）
    module/module_state_repository.dart  # module_state 读写（#44，停用只改一列）
    module/module_data_cleaner.dart      # 按 ownedTables 计数与清空（#45）
    module/module_providers.dart#   启用集合 / 排序 / 模块上下文 / 痕迹存储的 provider（#44/#45）
    last_module_store.dart      #   「上次停留模块」落 last_module.json（#44，不入库、不随备份）
    router.dart                 #   ⚠️ createAppRouter + resolveInitialLocation + resolveModuleRedirect（#44/#45）
    backup/                     #   整库备份恢复（#45 从 finance 提到 core）
    pin/                        #   PIN 锁凭据与校验（#45 从 finance 提到 core）
    files/file_save_picker.dart #   另存为（Android SAF / 桌面路径）
  data/db/app_database.dart     # ⚠️ 全模块装配点：9 张表 + 枚举 + AppDatabase 同文件，schemaVersion = 3
  modules/finance/              # ← #42 搬迁后的位置
    domain/                     #   纯逻辑：position_valuation / net_worth / price_provider /
                                #   recurring_logic / stats / csv_export
                                #   repositories/*.dart（8 个仓储接口）
    data/
      dao/*.dart                #   6 个 DAO（account/transaction/category/budget/recurring/position）
      repositories/*_impl.dart  #   8 个实现
      price/tencent_price_provider.dart  # 腾讯行情（GBK 解码，字段[3]现价/[30]时间）
    ui/{transactions,reports,accounts,positions,recurring}/
    ui/settings/csv_export_section.dart  # 向系统设置页贡献的「数据导出」条目（#45）
    finance_module.dart         #   ⚠️ 模块声明：id/name/order/ownedTables/tableLabels/routes/quickActions/settingsTiles（#44/#45）
    finance_providers.dart      #   finance 自己的 9 个仓储 provider（#45）
    ui/finance_shell.dart       #   模块内部四 tab + 左下角回 launcher 的出口（#44）
  modules/notes/                # ← v2.0 第一个**新增**模块（#47）
    domain/note_text.dart       #   纯逻辑：noteDisplayTitle（空标题退化正文首行）/ formatNoteTime
    domain/repositories/note_repository.dart
    data/dao/note_dao.dart      #   watchNotes 的排序在这里（置顶 → updatedAt → id 兜底）
    data/repositories/note_repository_impl.dart  # updatedAt 由这里维护；now 可注入便于测
    ui/{notes_page,note_edit_dialog}.dart
    notes_module.dart           #   模块声明：ownedTables = {notes}，路由 /notes，「写一条」快捷
    notes_providers.dart        #   noteRepositoryProvider + notesProvider
  ui/                           # core 级外壳
    launcher/launcher_page.dart # ⚠️ 应用首页九宫格 + 快捷动作，不认识任何具体模块（#44）
    settings/settings_page.dart # ⚠️ core 系统设置 + 各模块 settingsTiles（#45）
    settings/module_management_page.dart  # 启用/停用/清理/排序（#45）
    lock/                       #   PIN 锁屏与门卫
test/                           # 478 个单测 + Widget 测试
test/architecture/              #   ⚠️ 模块边界扫描：越界访问他人表 / import di.dart / core 反向依赖（#46）
test/fixtures/schema_v{1,2}.sql #   迁移测试用的真实 DDL 夹具（新增 migration 时补一份，不要改旧的）
integration_test/money_paths_test.dart   # ⚠️ 13 条碰钱路径，只允许这一个文件（见铁律 6）
docs/{ai-changelog,troubleshooting,issues-backlog,money-paths-coverage}.md
wiki/                           # 需求与流程的唯一权威来源（GitHub wiki 的副本）
scripts/                        # 32 个流水线/环境脚本，见 §9
```

**⚠️ 导入风格**：`lib/` 内一律用 `package:worthtrack/...` 绝对路径（#42 统一），
不要写相对 `../`——历史上 `lib/domain/repositories/` 里有 4 处写成 `../../../data/db`，
实际指向仓库根，潜伏了很久才在搬迁时暴露。

**当前 8 张表**：accounts / categories / transactions / budgets / recurring_rules / positions / price_cache / **module_state**（core 拥有）。

---

## 4. 铁律（违反会直接翻车，别自行放宽）

1. **AI 读需求只从 `wiki/` 读**（GitHub wiki 是权威，Obsidian vault 只是起草区）。
2. **schemaVersion 现为 2**（v1→v2 已在 #43 完成，加 `module_state` 表）。
   之后任何升级**只在 `onUpgrade` 按 `if (from < N)` 追加分支**，禁止改动旧表结构历史，
   且必须配迁移测试（做法见 `test/data/migration_v1_to_v2_test.dart`：用真实 v1 库夹具升级后逐表比对）。
3. **金额只用整数分**，任何浮点金额都是 bug。
4. **碰钱路径（写交易/改余额）必须在同一事务内**完成。
5. **CI 三关硬门槛**：`dart format --set-exit-if-changed` + `flutter analyze --fatal-warnings` + `flutter test` 全绿。
6. **`integration_test/` 只允许一个文件**（多文件时第二个应用启动必挂，见 troubleshooting 1.5）。
7. **每个 issue 一个分支 + 一个 PR**，Conventional Commits，合并前逐 step 核对 CI（`scripts/job_steps.sh`），不能只看总时长。
   **v2.0 起改为两级分支**：`issue 分支 → feat/m5-modular → main`，M5 收口时整体 PR 到 main。
   注意：合入非默认分支时 GitHub **不会**自动关闭 issue（`Closes` 只认默认分支），要手动关并留痕。
8. **新增 DAO 必须注册进 `@DriftDatabase(daos:)`**，否则 `.g.dart` 静默不生成 getter（troubleshooting 2.5）。
9. **建 PR 的脚本只 POST 不查重**，别重复跑 `pr_pipeline.py`。
10. **v2.0 起禁止出现「动态加载」四个字**，正确说法是「模块化装配 + 运行时门禁」（原因见 §6）。
11. **模块不 import `di.dart`**（#45 起的分层）：core 服务从 `core/providers.dart` 拿，
    自己的仓储放模块内的 `*_providers.dart`；`di.dart` 只做 re-export，是装配入口。
    `core/` 也不许反向 import 模块——唯一例外是 `module_registry.dart` 的注册表与 `di.dart`。
    **这条不是靠自觉**：#46 的 `test/architecture/` 会扫源码，越界直接让 PR 变红。
12. **新增表要同步三处**：`AppDatabase` 的表定义、某模块的 `ownedTables`、`test/architecture/module_boundary_rules.dart` 的 `knownTables`。
    漏了第三处，越界扫描会静默漏掉那张表（有专门的用例守着）。

---

## 5. 已完成（不需要重做）

| 里程碑 | 状态 | 产物 |
|---|---|---|
| M1 记账核心 | ✅ | v0.1.0 |
| M2 报表与预算 | ✅ | v0.2.0 |
| M3 投资跟踪 | ✅ | v0.3.0（持仓、行情、缓存兜底、净资产、PIN 锁） |
| M4 备份与打磨 | ✅ | v0.4.0（备份恢复 #18、CSV #19、集成测试补齐 #21、文档 #22） |

- 最新 Release **v1.0.0**（2026-10-31，M1–M4 能力封板版，代码与 v0.4.0 完全一致）：
  `app-release.apk` 58.0 MB + `worthtrack-linux-x64.tar.gz` 19.5 MB
- 测试基线：**478 个单测/Widget + 13 条集成测试**（299 为 v0.4.0 基线，+17 模块契约、+9 schema v2 迁移/备份、+56 launcher/路由/模块状态、+42 模块管理/清理/路由门禁、+21 架构边界、+34 notes 数据层/schema v3/模块/页面）

---

## 6. v2.0 已定稿的 8 项决策（已写进 wiki，不要重新讨论）

| # | 决策 | 关键理由 |
|---|---|---|
| 1 | 定位 = **个人工具箱**（不是「个人助手」） | 「助手」暗示主动推送/聚合/编排，与「纯本地、无后台」冲突，且不回答"何时打开" |
| 2 | 首页 = **launcher + 常驻「记一笔/记一条」+ 恢复上次模块（30 分钟超时）** | 纯 launcher 会让记账变 2 步，用户会弃用 |
| 3 | 机制 = **模块化装配 + 运行时门禁** | Dart AOT 无法运行时加载代码；deferred components 仅限 Play 分发，本项目自签 APK 走不通 |
| 4 | 数据 = **单库 + 表所有权 + 弱引用**（`refType`/`refId`，不建外键） | 净资产 = 现金余额 + 持仓市值，必须同一事务视图；拆库会让核心口径失效 |
| 5 | 开关 = **停用**（隐藏，数据不动）与**清理**（删数据，二次确认）两个动词 | 合并会导致「只想隐藏却丢数据」或「想删干净却删不掉」 |
| 6 | 目录 = finance 整体迁入 `lib/modules/finance/` | 用户明确选择彻底搬迁 |
| 7 | 监测 = **仅前台轮询 + 应用内提醒** | 后台推送要同时对付通知权限、电池白名单、厂商杀后台、桌面无统一方案 |
| 8 | 游戏 = **一个**最小离线小游戏，范围锁死 | 目的是验证"加模块 = 加目录 + 注册一行"，不是做游戏 |

**两个在定稿时发现的设计漏洞（必须遵守）：**

- **设置页死锁**：现有设置页跨 core/finance。若它随 finance 模块走，停用 finance 后用户再也进不了模块管理页 → **系统设置（PIN/备份恢复/模块管理）必须归 core**，模块只通过 `AppModule.settingsTiles` 贡献条目。
- **Drift 中央装配点**：`@DriftDatabase(tables: [...])` 必须集中声明，`app_database.dart` 无法模块化。目标改为「**表定义归模块，装配归中央**」，别追"完全独立"这个不存在的目标。

完整需求：`wiki/需求规格-v2.0.md`；决策与排除理由：`wiki/模块化架构决策.md`。

---

## 7. 未解决清单（按性质分四类）

### A. 阻塞项（动手前必须先处理）

1. ~~M5–M8 的 16 条 issue 还没建到 GitHub~~ → **已解决（2026-10-31）**：已建 #41–#56，
   标签 M5/M6/M7/M8 已创建，`docs/issues-backlog.md` 已回填编号。
   建 issue 用 `scripts/create_issues_v2.py`（**幂等**，按标题查重，可重复跑；`--dry-run` 先看）。
   ⚠️ 旧的 `scripts/create_issues.py` **没有查重**且含 M1–M4 全部 22 条，再跑会重复建，别用。
2. ~~还没建 v2.0 分支~~ → **已解决**：`feat/m5-modular` 已创建并推送到 origin。
3. ~~**v1.0.0 要不要发**~~ → **已解决（2026-10-31）**：真机手测通过后已发 v1.0.0
   （`app-release.apk` 58.0 MB + Linux 包），M1–M4 能力封板。v2.0 走 v2.0.0 版本号，
   真机手测合并进 v2.0 的出口条件（M8 发版前按清单走一遍）。

### B. 待用户拍板（我给了建议，但没有得到确认，别自己替他定）

| 问题 | 我的建议 |
|---|---|
| 版本号用 v2.0.0 还是 v1.1.0 | **v2.0.0**：导航重构 + 目录重构 + schema v2，三项都是破坏性变更 |
| 游戏具体做哪一个 | 2048 或扫雷；标准是「单文件可读完、无资源包」 |
| launcher 排序是否允许拖拽 | 允许，`module_state` 已有 order 字段；但先做固定顺序，拖拽放 M8 |
| 自选列表与持仓如何去重 | 同一 `code` 合并为一条，来源标记 `held` / `manual`，默认显示持仓、可单独隐藏 |
| 提醒去重口径 | 按「当日一次」实现（简单、可测）；「再次穿越才提醒」留到 v2.x |
| 记事本 Markdown 怎么渲染 | 自研轻量（粗体/列表/标题三件套），不引 `flutter_markdown`，避免新依赖与新测试面 |
| 桌面宽屏 launcher 布局 | 手机九宫格，宽屏改两列列表；**需求里「桌面同款布局」这条在 launcher 上不成立，需要确认放宽** |
| **旧版本备份能不能恢复**（v2 新增，**阻断 v2.0 发布**） | 现状 `validateBackup` 拒绝任何旧版本备份 → v2 上线后用户升级前的 v1 备份**无法恢复**。放开的技术前提已具备（只替换备份中存在的表 + 单事务回滚），但这是产品取舍，需拍板 |

### C. 技术上待验证（有把握能做，但没验证过，别当成已知）

1. **`onUpgrade` 加表的具体写法**：Drift `Migrator.createTable` 的正确姿势 + 迁移测试怎么造 v1 库（`test/helpers/sqlite3_loader.dart` 已有基建）。这是本项目**第一次写 migration**，别凭记忆写。
2. **`go_router` 版本与 `StatefulShellRoute.indexedStack` 在 3.35 的 API**：项目现在零路由库、纯 `Navigator`，引入即一次导航重构。
3. **集成测试的组织方式**（真问题）：铁律 6 只允许一个集成文件，但 v2.0 有 4 个模块。塞进一个文件会膨胀到难以维护。**需要先定方案**：按 `group()` 分段（保守）还是冒险拆分（已知多文件会挂）。
4. **搬迁的机械性验证**：65 个 dart 文件移动后，如何证明「零功能变化」——建议断言 `flutter test` 数量**精确等于 299**，且该提交内不含 `feat:`。

### D. 已知风险（不是待办，是要盯着）

- **完成度落差**：finance 有 299 个测试，新模块可能只有十几个；同一个 App 里落差会很明显。
- **游戏成本易低估**：项目没有游戏循环/音频/资源打包经验，若超预期就砍。
- **行情接口限流**：腾讯行情是未公开免费接口，高频轮询会被限流甚至封 IP，"实时"有天花板。
- **后台推送已明确推迟**到 v2.x，产品文案必须写清"打开 App 才提醒"，别让用户自己发现。

---

## 8. 执行顺序

### M5 模块化（✅ 已全部合入 main，PR #65）

| 序 | 任务 | 验收标准 |
|---|---|---|
| 1 | #41 抽 `core/` + 定义 `AppModule` / `ModuleContext` | ✅ 已完成（PR #57） |
| 2 | #42 finance 整体迁入 `lib/modules/finance/` | ✅ 已完成（PR #58，测试数 316） |
| 3 | #43 schema v2：`module_state` 表 + 首次 `onUpgrade` | ✅ 已完成（PR #59） |
| 4 | #44 launcher + `go_router` 导航 | ✅ 已完成（PR #62）：冷启动恢复上次模块 / 30 分钟超时 / 「记一笔」1 步 |
| 5 | #45 模块管理页 + 设置页拆分 | ✅ 已完成（PR #63）：停用/清理独立入口；停用全部模块后仍能进模块管理重新启用 |
| 6 | #46 架构测试 | ✅ 已完成（PR #64）：扫源码守三条边界，`ownedTables` ↔ schema 双向一致，规则本身有自检用例 |

### M6 记事本（下一个）

| 序 | 任务 | 验收标准 |
|---|---|---|
| 1 | #47 `notes` 表 + DAO + 仓储 | 新表登记进 `ownedTables` 与 `knownTables`（漏了架构测试会红）；模块可独立停用 |
| 1 | #47 `notes` 表 + DAO + 仓储 | ✅ 已完成：schema v3（只加表）、`ownedTables`/`knownTables` 已登记、迁移测试覆盖 v1→v3 与 v2→v3 |
| 2 | #48 记事本页（列表 / 编辑 / 置顶 / 搜索） | 列表与编辑已在 #47 落地（模块注册必须有路由，否则 launcher 会点到 404）；#48 补置顶交互 / 搜索 / 排序打磨 |
| 3 | #49 弱引用：从标的或账户跳到相关笔记 | 弱引用 = 存 id 不建外键，删了也不报错 |
| 4 | #50 模块停用/清理对 notes 数据的正确性 | 「清理数据」只删 notes 自己的表，finance 一条不动 |

之后：M7 关注与提醒 → M8 游戏与发版。

---

## 9. 常用命令

```bash
# 全部走 WSL 包装脚本
bash scripts/wt_flutter.sh flutter test --reporter compact
bash scripts/wt_flutter.sh dart format lib test integration_test
bash scripts/wt_flutter.sh flutter analyze --fatal-warnings

# drift 代码生成（改表后必跑）
bash scripts/wt_flutter.sh bash -c 'flutter pub get && dart run build_runner build --delete-conflicting-outputs'

# 建 PR / 轮询 / 核对 / 看板
python3 scripts/pr_pipeline.py <branch> <issue> '<title>' .pr_body.md
python3 scripts/poll_pr.py <pr_no> 2400
bash scripts/job_steps.sh <sha>          # 逐 step 核对，确认集成测试真跑了
python3 scripts/board_done.py <issue...>

# 发版
git tag vX.Y.Z && git push origin vX.Y.Z
python3 scripts/wait_release.py vX.Y.Z 40
bash scripts/set_release_body.sh vX.Y.Z
```

---

## 10. 新会话最易踩的 5 个坑

1. **新增 DAO 忘注册**进 `@DriftDatabase(daos:)` → `.g.dart` 静默无 getter（troubleshooting 2.5）
2. **GBK 切分错位**：腾讯行情必须先 `fast_gbk` 解码再按 `~` 切，中文名含 0x7E 会导致列偏移（2.7）
3. **`library;` 必须放在 import 之前**，否则 analyze 报错（2.10）
4. **测试文案重复**：同一句文案同时出现在按钮与弹窗标题 → finder 命中 2 个，改用 `find.byKey`（3.4）
5. **WSL 卡死**：本会话就遇到一次（`wsl.exe -l -v` 无响应、`--shutdown` 也挂）。恢复办法：管理员 PowerShell 执行 `wsl --shutdown` 后重开。**push 依赖 WSL 内的 SSH key**，Windows 侧 `git push` 会报 `Permission denied (publickey)`。

---

## 11. 第一天 checklist

- [ ] 跑完 §1 四条验证命令，确认 444 个测试全绿
- [ ] 读 `wiki/需求规格-v2.0.md` + `wiki/模块化架构决策.md`
- [ ] 读 §8 的 M5 表格，理解「core + 模块」的分层与三条边界
- [ ] 从 M6 第一条 #47 开始
