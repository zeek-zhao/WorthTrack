# WorthTrack 问题与解决方法记录（Troubleshooting Log）

> **维护约定（长期有效）**：凡是开发过程中实际踩到、并确认已解决的问题，必须在本次开发会话结束前登记到本文档对应章节；格式统一为「现象 → 根因 → 解决 → 预防」。本文档与 `docs/ai-changelog.md`（改动流水）互补：changelog 记"改了什么"，本文档记"为什么踩坑、以后怎么避"。

## 目录

- [1. CI/CD 与 GitHub Actions](#1-cicd-与-github-actions)
- [2. Drift / 数据库](#2-drift--数据库)
- [3. Flutter 测试](#3-flutter-测试)
- [4. WSL 环境与工具链](#4-wsl-环境与工具链)
- [5. GitHub API 与权限](#5-github-api-与权限)
- [6. 签名与发布](#6-签名与发布)

---

## 1. CI/CD 与 GitHub Actions

### 1.1 CI 显示 startup_failure，0 个 job 启动

- **现象**：push 后 Actions 页面只显示 `startup_failure`，没有任何 job 日志。
- **根因**：在 job 级使用 `if: ${{ hashFiles(...) }}`——`hashFiles` 函数只在 step 级可用，workflow 解析阶段直接失败。
- **解决**：删掉 job 级 `hashFiles` 守卫，改为 step 内用 `if [ -d integration_test ]` 的 shell 条件判断。
- **预防**：GitHub Actions 表达式函数的作用域限制，在写 job 级条件前先查官方文档。

### 1.2 本地通过、CI 却挂 dart format

- **现象**：本地 `dart format` 无差异，CI 的 format 门禁却报文件需要重排。
- **根因**：CI 用 `channel: stable` 浮动版本，上游 Flutter/Dart 升级后 format 规则变了，与本地钉住的版本不一致。
- **解决**：CI 的 `flutter-version` 钉死为 `3.35.4`（与 WSL 本地一致），质量门禁和 release job 都钉同一版本。
- **预防**：**凡是影响产出的工具版本一律钉死**，不允许 stable/mainline 浮动。本地升级 Flutter 时同步改 CI。

### 1.3 tag 推送不触发发布流水线

- **现象**：打了 `v0.1.0` tag，CI 没有跑 release job。
- **根因**：`on.push` 只配了 `branches: [main]`，没有 `tags` 过滤器；push tag 不在触发范围内。
- **解决**：`on.push.tags: ['v*']`；同时修正历史 tag（删旧重打，`git push origin :refs/tags/v0.1.0` + 重打）。
- **预防**：新增触发方式后用一次真实 push 验证，不靠想象。

### 1.4 Create Release 403（默认 GITHUB_TOKEN 无权限）

- **现象**：release job 在创建 Release 步骤报 403。
- **根因**：默认 `GITHUB_TOKEN` 的权限受 workflow 级 `permissions` 限制，未授予 contents 写权限。
- **解决**：release job 加 `permissions: contents: write`。注意：**permissions 修改对已存在的 tag 不回溯生效**，需要删 tag 重打才会用新配置跑。
- **预防**：改动 workflow 权限后，必须重新触发一次完整流水线验证，不能只看语法。

### 1.5 多个集成测试文件时，第二个文件的应用启动稳定失败

- **现象**：`xvfb-run flutter test integration_test` 下，第一个文件 3 条用例全过，第二个文件报 `Error waiting for a debug connection: The log reader stopped unexpectedly`，稳定复现（2/2），与测试内容无关。
- **根因**：每个集成测试文件都要独立构建并启动一次 Linux host 应用；本 CI 环境（xvfb 虚拟显示）下第二次启动不可用，具体机制未深究。
- **解决**：所有集成用例合并进单文件 `integration_test/money_paths_test.dart`，一次应用启动跑完全部碰钱路径。
- **预防**：M2 起集成测试**只允许一个文件**；新增碰钱路径用例往 money_paths_test.dart 里追加 testWidgets。

### 1.6 check-runs 里 skipped 的 job 让自动化轮询误判"CI 失败"

- **现象**：PR 上 quality job 全绿，轮询脚本却报 `Build & Release=skipped ... CI FAILED` 并退出。
- **根因**：`/commits/{sha}/check-runs` 会把 tag 专属的 release job 也列进来（在 PR 上结论是 skipped）；脚本用 `all(conclusion == "success")` 判断。
- **解决**：`scripts/poll_pr.py` 判定改为 success/skipped 均视为通过（release job 只在 tag 上运行）。
- **预防**：基于 check-runs 的自动化必须显式处理 `skipped`/`neutral` 结论。

## 2. Drift / 数据库

### 2.1 intEnum 列在生成代码里静默丢失（最高优先级陷阱）

- **现象**：表定义里有 `intEnum<T>()` 列，`build_runner` 不报错，但生成的 `.g.dart` 里该列直接不存在，运行时建表/查询异常。
- **根因**：drift_dev 2.29–2.31（Dart 3.9 能用的最后一批版本）在**枚举与表定义跨文件布局**下的代码生成 bug，已在最小工程中复现确认。
- **解决**：枚举定义、全部表、`@DriftDatabase` 类保持在同一个 `app_database.dart` 文件内。等 Flutter 升到 Dart ≥3.10（可用 drift ≥2.33）后再验证能否拆分。
- **预防**：升级 drift/Flutter 后，先在最小工程验证拆分布局，再动主工程。schema 相关改动后必须跑 `test/data/app_database_test.dart` 确认列完整。

### 2.2 intEnum getter 忘写结尾括号

- **现象**：`IntColumn get type => intEnum<AccountType>;` 编译报类型错误。
- **根因**：`intEnum<T>()` 是函数调用，漏了 `()`。
- **解决**：补上括号。同批还确认 DAO 必须写 `@DriftAccessor(tables: [...])` 参数，空参数会生成空 mixin。
- **预防**：无（基础语法问题，靠 analyze 兜底）。

### 2.3 watchByMonth 月份边界串月

- **现象**：某月的查询把上月/下月的数据带进来。
- **根因**：用了 `isBetweenValues`（双端闭区间），月末最后一天的 23:59:xx 落到边界外。
- **解决**：月份过滤统一用**左闭右开**区间：`occurredAt >= 当月1日0点 AND occurredAt < 次月1日0点`（`DateTime(y, m+1)` 自动进位年份）。
- **预防**：所有时间范围过滤统一左闭右开，这是全项目的固定约定。

### 2.4 selectOnly 聚合与 type converter 不兼容

- **现象**：对 intEnum 列所在表用 `selectOnly` 做聚合时报类型错误。
- **根因**：drift 的 `selectOnly` 与 `GeneratedColumnWithTypeConverter` 的兼容性问题（2.29 版本）。
- **解决**：改为普通 `select` 拉行后在 Dart 端聚合（账户表行数很小，性能无影响）。
- **预防**：涉及枚举列的统计优先 Dart 端聚合；纯数值列的 SQL 聚合（如 sum 余额）不受影响，可继续用 `selectOnly`。

### 2.5 新增 DAO 只建文件不注册 → 库上没有 xxxDao getter

- **现象**：新建 `position_dao.dart` 并跑完 `build_runner`，代码里 `db.positionDao` 报「未定义」；`build_runner` 输出 **EXIT=0 且无报错**，`position_dao.g.dart` 也正常生成（mixin 有了），只有 `app_database.g.dart` 里少了 `late final PositionDao positionDao = ...`。
- **根因**：DAO getter 是由 `@DriftDatabase(daos: [...])` 列表驱动生成的；只写 `@DriftAccessor` 只会生成 mixin，不会往 `AppDatabase` 上挂 getter。生成器对「孤儿 DAO」不告警。
- **解决**：把 `PositionDao` 加进 `app_database.dart` 的 `daos:` 列表（并 import），重跑 `build_runner`，确认 `.g.dart` 里出现 `late final PositionDao positionDao`。
- **预防**：新增 DAO 的检查清单 = ① 文件带 `part 'x_dao.g.dart'` ② 类带 `@DriftAccessor(tables: [...])` ③ **`@DriftDatabase(daos:)` 里注册** ④ 重跑生成后 grep 一下 `.g.dart` 确认 getter 存在。

### 2.6 自定义主键表生成的行类名不是表名

- **现象**：`PriceCache` 表（`primaryKey => {symbol}`，无 autoIncrement id）生成的行类是 **`PriceCacheData`**，写成 `Map<String, PriceCache>` / `Future<PriceCache?>` 全部类型报错（`PriceCache` 是 Table 类，字段是 `IntColumn` 而非 `int`）。
- **根因**：drift 只在「单列 autoIncrement 主键」时才把行类命名为 `<Table>`，否则生成 `<Table>Data`；表类本身仍是 `PriceCache`。
- **解决**：行类型统一写 `PriceCacheData`，Companion 仍是 `PriceCacheCompanion`。
- **预防**：写新表时先看生成的 `.g.dart` 里 `class XxxData` 还是 `class Xxx`，再定 DAO 的返回类型。

## 3. Flutter 测试

### 3.1 Widget 测试收不到广播流的"历史"数据

- **现象**：`pumpWidget` 之后往 broadcast StreamController 里 add 数据，UI 不更新。
- **根因**：broadcast 流不缓存历史，订阅发生在 add 之后（或订阅时序与 pump 交错），错过事件。
- **解决**：假仓储统一用 replay-on-subscribe 包装（`test/helpers/fake_transaction_repository.dart` 的 `replayStream`）：每次订阅先补发当前值，再透传后续事件。
- **预防**：新增假仓储一律复用 `replayStream`；测试中先 pump 建立订阅、再推数据、最后 `pumpAndSettle`。

### 3.2 WSL 本地跑 flutter test 报 libsqlite3 找不到

- 见 [4.1](#41-wsl-缺少-libsqlite3-免-sudo-解决)。

## 4. WSL 环境与工具链

### 4.1 WSL 缺少 libsqlite3（免 sudo 解决）

- **现象**：`flutter test` 里 Drift 的 `NativeDatabase` 报 `Failed to load dynamic library libsqlite3.so`。
- **根因**：Ubuntu 24.04 WSL 没装系统级 sqlite3 开发库，且不想用 sudo 动系统。
- **解决**：`scripts/setup_sqlite3_local.sh` 用 `apt-get download` 把 `.deb` 下载解包到 `~/.local/lib`，测试里通过 `test/helpers/sqlite3_loader.dart` 在 `setUpAll` 里 `DynamicLibrary.open` 绝对路径加载。
- **预防**：新环境初始化先跑该脚本；集成测试在 CI 的 Linux runner 上跑（runner 自带工具链），本地 WSL 跑集成测试需要 sudo 装同款工具链（clang/cmake/ninja/libgtk-3-dev/xvfb）。

### 4.2 从 Windows 调 wsl.exe 时路径被 MSYS 转换

- **现象**：`wsl.exe ls /mnt/d/...` 的参数被 Git Bash 转换成 Windows 路径（`D:\...`），命令在 WSL 里跑飞。
- **根因**：MSYS2/Git Bash 的自动路径转换（POSIX path conversion）。
- **解决**：命令前加 `MSYS_NO_PATHCONV=1`。
- **预防**：所有经 Git Bash 发起的 wsl.exe 调用统一带该前缀。

### 4.3 多层 shell 嵌套时 `$(cat file)` 展开被污染

- **现象**：keystore 密码通过 `wsl.exe bash -c "... $(cat 密码文件) ..."` 传递，密码变成空串，签名报 `Cannot recover key`。
- **根因**：`$(cat ...)` 在 Windows 侧 shell 就被展开（拿到空值/被转义破坏），到 WSL 内已经不是预期内容；引号多层嵌套时尤其隐蔽。
- **解决**：**密码/文件内容一律不走命令行内联**。写脚本文件（`local_release.sh`、`upload_signing_secrets.py`），脚本内部读文件；敏感文件权限 600。
- **预防**：铁律——凡是嵌套超过一层 shell 的命令，写成 `scripts/` 下的脚本文件执行；密钥类内容永远文件内流转。

## 5. GitHub API 与权限

### 5.1 fine-grained token 调 Projects (GraphQL) 403

- **现象**：REST（issues/PR）正常，GraphQL ProjectsV2 调用 403。
- **根因**：fine-grained token 的权限模型没有覆盖 GraphQL ProjectsV2。
- **解决**：换 classic token（勾选 repo + 适当 scope）后正常；Projects 看板操作走 `scripts/create_project_board.py` / `set_board_status.py`。
- **预防**：涉及 GraphQL 的新操作，先小请求验证 token 权限再写流程。

### 5.2 PR 多行 body 被换行拆散

- **现象**：`gh pr create --body "多行文本"` 的 body 在嵌套 shell 里被按行拆成多个参数。
- **根因**：多层 shell 传递时换行与引号丢失。
- **解决**：`scripts/pr_pipeline.py` 的 body 参数改为**传文件路径**，脚本内部读文件内容。
- **预防**：与 4.3 同源——嵌套 shell 中绝不直接传多行/含特殊字符文本，一律文件化。

### 5.3 嵌套引号导致 curl + python 内联脚本失败

- **现象**：`wsl.exe bash -c "curl ... | python3 -c 'import json...'"` 报 KeyError/语法错。
- **根因**：Windows shell → bash -c → python -c 三层引号转义互相污染。
- **解决**：写成仓库内临时脚本（如 `scripts/fetch_issues.py`）执行。
- **预防**：同 4.3。

## 6. 签名与发布

### 6.1 PKCS12 keystore 在 CI 报 "Tag number over 30"

- **现象**：用 PKCS12 格式 keystore 签名时，CI 报 keystore 解析错误。
- **根因**：PKCS12 + 特定 JDK/工具链组合的兼容性问题。
- **解决**：keystore 改用**传统 JKS 格式**生成（`scripts/gen_keystore.sh`）。
- **预防**：生成 keystore 固定用 `gen_keystore.sh`，不要手工指定 PKCS12。

### 6.2 keystore 与密码的安全流转

- **约定**（长期有效）：
  - keystore 本体：WSL `~/worthtrack-keys/upload-keystore.jks`，**不进仓库**（`android/app/` 下的副本已 gitignore）。
  - 密码：WSL `~/.config/worthtrack/ks_pass`（600），CI 侧在 GitHub Secrets（KEYSTORE_BASE64 / KEYSTORE_PASSWORD / KEY_ALIAS / KEY_PASSWORD）。
  - 流转一律脚本内读文件，见 4.3。
- **提醒**：keystore 丢失将无法给已装用户推送升级，务必自留一份离线备份。

---

## 附：固定约定速查

| 约定 | 内容 |
| --- | --- |
| Flutter 版本 | 本地与 CI 统一钉 3.35.4 |
| drift 版本 | 2.29.x，枚举+表+库单文件（见 2.1） |
| 时间过滤 | 一律左闭右开（见 2.3） |
| 金额存储 | 全部整数分，`lib/core/money.dart` 转换 |
| WSL 命令 | `MSYS_NO_PATHCONV=1`；复杂命令写 scripts/ 脚本 |
| 敏感信息 | 永不命令行内联，脚本内读文件 |
| 发版 | tag `vX.Y.Z` → CI 全绿 → 签名 APK + Linux 包自动上 Release |
