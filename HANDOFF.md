# WorthTrack 交接文档（给接手的 AI）

> 生成时间：2026-10-31 ｜ 交接点：**v0.4.0 已发布，v2.0 需求刚定稿，v2.0 代码尚未开始**
> 读这一份即可接手，不需要回溯历史对话。更细的历史坑见 `docs/troubleshooting.md`，改动流水见 `docs/ai-changelog.md`。

---

## 0. 一句话现状

`main = f680786`，工作区干净，与 origin 同步；**v0.4.0 已发布**（APK + Linux 包），v1.0.0 发版说明已写好待打 tag；
M1–M4 共 22 个 issue 全部关闭；**v2.0 的 16 条 issue 已建（#41–#56）**；
M5 已开工：**#41 完成**（core 模块契约，PR #57 合入 `feat/m5-modular`），下一步 #42。

---

## 1. 先做这四件事（验证环境）

```bash
cd /d/zeek/WorkBuddy/WorthTrack
git log --oneline -3                                  # 应为 9464a2f 起
bash scripts/wt_flutter.sh flutter --version          # 应为 3.35.4 / Dart 3.9.2
bash scripts/wt_flutter.sh flutter test --reporter compact   # 应为 299 个全绿
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
  di.dart                       # ⚠️ 全量 Riverpod Provider 注册（单点，模块化后禁止模块 import 它）
  core/money.dart               # 分↔元转换
  core/stream_utils.dart        # combineLatest2/3，组合多个 drift watch 流
  domain/                       # 纯逻辑，无 Flutter 依赖
    position_valuation.dart     #   持仓市值/成本/盈亏 + 汇总
    net_worth.dart              #   ⚠️ 净资产口径 + 历史曲线反向回溯
    price_provider.dart         #   Quote / QuoteStatus / PriceRefreshReport
    recurring_logic.dart        #   周期账单补生成
    stats.dart                  #   报表聚合
    backup.dart / csv_export.dart / pin_lock.dart
    repositories/*.dart         # 10 个仓储接口
  data/
    db/app_database.dart        # ⚠️ 7 张表 + 枚举 + AppDatabase 必须同文件，schemaVersion = 1
    dao/*.dart                  # 6 个 DAO（account/transaction/category/budget/recurring/position）
    price/tencent_price_provider.dart   # 腾讯行情（GBK 解码，字段[3]现价/[30]时间）
    backup/database_backup_repository.dart  # VACUUM INTO 导出 / ATTACH + 单事务恢复
    pin/pin_store.dart          # PIN 凭据落 <应用支持目录>/pin_lock.json（不进 DB）
    repositories/*_impl.dart    # 10 个实现
  ui/
    home_page.dart              # ⚠️ IndexedStack + 5 个硬编码 tab（v2.0 要拆成 launcher）
    transactions/ reports/ accounts/ positions/ recurring/ lock/ settings/
test/                           # 299 个单测 + Widget 测试
integration_test/money_paths_test.dart   # ⚠️ 13 条碰钱路径，只允许这一个文件（见铁律 8）
docs/{ai-changelog,troubleshooting,issues-backlog,money-paths-coverage}.md
wiki/                           # 需求与流程的唯一权威来源（GitHub wiki 的副本）
scripts/                        # 31 个流水线/环境脚本，见 §9
```

**当前 7 张表**：accounts / categories / transactions / budgets / recurring_rules / positions / price_cache。

---

## 4. 铁律（违反会直接翻车，别自行放宽）

1. **AI 读需求只从 `wiki/` 读**（GitHub wiki 是权威，Obsidian vault 只是起草区）。
2. **schemaVersion 仍是 1，从未写过 migration**。v2.0 加表将是本项目**第一次写 `onUpgrade`**，必须配迁移测试。
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

---

## 5. 已完成（不需要重做）

| 里程碑 | 状态 | 产物 |
|---|---|---|
| M1 记账核心 | ✅ | v0.1.0 |
| M2 报表与预算 | ✅ | v0.2.0 |
| M3 投资跟踪 | ✅ | v0.3.0（持仓、行情、缓存兜底、净资产、PIN 锁） |
| M4 备份与打磨 | ✅ | v0.4.0（备份恢复 #18、CSV #19、集成测试补齐 #21、文档 #22） |

- 最新 Release **v0.4.0**：`app-release.apk` 58.0 MB + `worthtrack-linux-x64.tar.gz` 19.5 MB
- 测试基线：**299 个单测/Widget + 13 条集成测试**（这是 v2.0 搬迁的锚点，见 §7）

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
3. **v1.0.0 要不要发**：wiki v1.0 验收标准第 3 条「真机手测清单逐项通过」一直没做，所以只有 v0.4.0。
   现在方向已转向 v2.0，需要你决定：**补发 v1.0.0（先在真机过一遍清单），还是直接奔 v2.0.0**。我倾向直接 v2.0.0，把真机手测合并进 v2.0 的出口条件。

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

## 8. 下一步执行顺序（M5 六条，不可跳）

> M5 全部完成前不要开 M6。顺序反了就是在移动的地基上盖房子。

| 序 | 任务 | 验收标准 |
|---|---|---|
| 1 | #41 抽 `core/` + 定义 `AppModule` / `ModuleContext` | 契约字段齐（id/name/icon/defaultOrder/dependsOn/ownedTables/routes/settingsTiles/onEnable/onDisable/onClear）；模块不 import `di.dart` |
| 2 | #42 finance 整体迁入 `lib/modules/finance/` | **纯重构提交**：`git mv` 保留历史、测试数精确 = 299、提交内无 `feat:` |
| 3 | #43 schema v2：`module_state` 表 + 首次 `onUpgrade` | 迁移测试：造 v1 库 → 升级 → 逐表比对无损 |
| 4 | #44 launcher + `go_router` 导航 | 每模块独立返回栈；冷启动恢复上次模块；30 分钟超时回 launcher；「记一笔」始终 1 步 |
| 5 | #45 模块管理页 + 设置页拆分 | 停用/清理是两个独立入口；**停用 finance 后仍能进模块管理页重新启用** |
| 6 | #46 架构测试 | 禁止跨模块访问他人表（按 `ownedTables` 校验）；禁止模块 import `di.dart`；`ownedTables` 与真实表一一对应 |

之后：M6 记事本 → M7 关注与提醒 → M8 游戏与发版。

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

- [ ] 跑完 §1 四条验证命令，确认 299 个测试全绿
- [ ] 读 `wiki/需求规格-v2.0.md` + `wiki/模块化架构决策.md`
- [ ] 把 §7-A 的三件阻塞项处理掉（建 issue、建分支、v1.0.0 去留问用户）
- [ ] 把 §7-B 的七个待定项一次性问清用户，不要边做边猜
- [ ] 再动 M5 第一条
