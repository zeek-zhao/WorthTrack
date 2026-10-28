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

### 2.7 腾讯行情响应按 UTF-8/latin1 解码后按 `~` 切分 → 列错位

- **现象**：解析 `v_sh600519="1~贵州茅台~600519~1355.90~...";` 时，偶尔出现「名称乱码 + 现价取到别的字段」。
- **根因**：腾讯接口返回 **GBK** 编码；GBK 双字节字符的尾字节范围是 `0x40–0xFE`，**`0x7E`（`~`）是合法尾字节**。用 latin1/utf8 解码后按 `~` 切分，名称里的字节会被误当分隔符，导致后续列整体错位（价格、涨跌等全部偏移）。
- **解决**：先 `gbk.decode(bodyBytes)`（`fast_gbk` 纯 Dart 实现，桌面/测试环境都能跑），再按 `~` 切分；解码失败时回退 `utf8.decode(allowMalformed: true)`。
- **预防**：第三方接口一律先确认编码（响应头 `Content-Type` 常不带 charset）；中文/非 ASCII 内容必须解码成 Unicode 后再做分隔符切分，不要对原始字节切分。

### 2.8 drift 列方法漏写括号（`isNull` / `isNotNull`）

- **现象**：`..where((p) => p.archivedAt.isNull)` 报 `The returned type 'Expression<bool> Function()' isn't returnable from a 'Expression<bool>' function`。
- **根因**：`isNull()` 是方法不是 getter，漏括号就变成函数 tear-off。
- **解决**：补 `()`：`p.archivedAt.isNull()`。
- **预防**：与 2.2 的 `intEnum<T>()` 同类，analyze 会拦住；写 where 子句时统一带括号。

### 2.9 「裁掉序列首段空档」写成取最小月 → 永远不裁

- **现象**：净资产序列本该只剩 1 个点（账户本月才建），实际返回 12 个点。
- **根因**：起点变量先赋成「窗口起点」（最早月），再用 `if (m.isBefore(start)) start = m` 去比「最早账目月」——只会把起点往**更早**推，永远不会裁掉前段。要的是 `max(窗口起点, 最早账目月)`。
- **解决**：先求最早账目月 `activityStart`，再取 `activityStart.isAfter(窗口起点) ? activityStart : 窗口起点` 作为保留起点。
- **预防**：凡「对齐/裁剪时间窗口」的代码，落笔前先写清要 min 还是 max；单测里必须有一条「窗口跨度 ≫ 数据跨度」的用例（如 12 个月窗口 + 本月才有账目）。

### 2.10 文件级文档注释写成 `library;` 却放在 import 之后

- **现象**：`Directives must appear before any declarations`（或 analyzer 把 `library` 当成非法指令）。
- **根因**：`library;` 是**指令**，必须排在所有 `import` 之前；想给整个文件写文档注释，注释和 `library;` 得一起放到文件最顶上。
- **解决**：`/// 文件说明` + `library;` 置顶，紧跟其后才是 `import`。
- **预防**：只给单个类/函数写注释就不需要 `library;`；要写「整个文件」的说明时先放指令再放 import。

### 2.11 `VACUUM INTO` 目标文件已存在 → 直接报错

- **现象**：导出备份时 `SQL logic error: output file already exists`。
- **根因**：`VACUUM INTO '<path>'` 的语义是「**新建**一个文件」，目标已存在就失败，不像普通文件写入会覆盖。
- **解决**：临时文件名带微秒时间戳（`worthtrack-export-<micros>.sqlite3`），写完读成字节后立刻删掉。
- **预防**：把 `VACUUM INTO` 当成「另存为」而不是「写入」，任何复用固定路径的写法都会踩。

### 2.12 `ATTACH DATABASE` 不能在事务里执行

- **现象**：`cannot ATTACH database within transaction`。
- **根因**：SQLite 明确禁止在活动事务内 ATTACH/DETACH。
- **解决**：顺序固定为 `ATTACH` → `BEGIN ... COMMIT` → `DETACH`；drift 侧就是「先 `customStatement('ATTACH …')`，再 `db.transaction(...)`」。
- **预防**：写「跨库搬数据」时先画一遍语句顺序，别把 ATTACH 塞进 `transaction {}` 里图省事。

### 2.13 恢复备份用「关库 + 覆盖文件」→ 流断掉且失败不可回滚

- **现象（设计阶段否决的方案）**：`db.close()` → `File.copy(备份, 库路径)` → 重建 Provider。问题有三：① 正在显示的 drift watch 流全部断开，必须重建整棵 Provider 树；② 复制到一半失败，用户既没有新数据也没有旧数据；③ 拿「应用正在使用的库文件」自己恢复时，等于先删再读，账本直接清空。
- **根因**：文件级替换把「数据正确性」交给了文件系统，SQLite 事务完全没用上。
- **解决**：改成 `ATTACH 备份库` + **单事务** `DELETE` 全表 + `INSERT … SELECT *`：
  - 事务内先 `PRAGMA defer_foreign_keys = ON`，外键（`categories` 还自引用）留到提交时统一校验，清空/写入都不必纠结顺序；
  - 失败整体回滚，UI 可以放心承诺「当前数据没有被改动」；
  - 连接不断，drift 的 watch 流自动收到变更，页面即时刷新；
  - 恢复前用 `PRAGMA database_list` 取主库路径，与候选文件比对，挡住「拿自己恢复」。
- **预防**：凡是「整体替换用户数据」的动作，优先想「能不能在一个事务里完成」，而不是「关掉再换文件」。

## 3. Flutter 测试

### 3.1 Widget 测试收不到广播流的"历史"数据

- **现象**：`pumpWidget` 之后往 broadcast StreamController 里 add 数据，UI 不更新。
- **根因**：broadcast 流不缓存历史，订阅发生在 add 之后（或订阅时序与 pump 交错），错过事件。
- **解决**：假仓储统一用 replay-on-subscribe 包装（`test/helpers/fake_transaction_repository.dart` 的 `replayStream`）：每次订阅先补发当前值，再透传后续事件。
- **预防**：新增假仓储一律复用 `replayStream`；测试中先 pump 建立订阅、再推数据、最后 `pumpAndSettle`。

### 3.2 WSL 本地跑 flutter test 报 libsqlite3 找不到

- 见 [4.1](#41-wsl-缺少-libsqlite3-免-sudo-解决)。

### 3.3 假仓储之间做「跨流自动联动」→ 断言被后到的派生值覆盖

- **现象**：测试里显式 `netWorthFake.emit(期望值)` 之后，卡片仍显示旧值；或反过来显式值把派生值盖掉，结果随机。
- **根因**：两个假仓储各自是 broadcast 流，事件异步投递。账户流事件触发的「重新计算并 emit」可能排在显式 emit **之后**，最后一个事件说了算；断言因此依赖投递顺序。
- **解决**：假仓储之间**不做隐式联动**，Widget 测试显式 emit 各自需要的值（账户变化后手动 emit 一次总览）；跨流组合交给生产代码的 `combineLatest3`，用真 Drift 在 `test/data/` 里测。
- **预防**：一个 Widget 测试只驱动被测 UI 真正需要的那几条流；任何「A 变化 → B 自动重算」的逻辑不要塞进测试替身。

### 3.4 同一句文案同时出现在按钮和弹窗标题 → finder 命中 2 个

- **现象**：`find.text('忘记 PIN？')` 报 `Found 2 widgets`，用例挂在 `findsOneWidget`。
- **根因**：锁屏页有「忘记 PIN？」按钮，重置弹窗标题也用了同一句；打开弹窗后两者同时在树上。
- **解决**：文案去重——弹窗标题改成「重置 PIN 锁？」，标题说动作、按钮说入口。
- **预防**：`findsOneWidget` 断言前先想「这句话在别的控件上是否也合理」；确实需要同文案时改用 `find.byKey` 定位，或断言 `findsNWidgets(2)`。

### 3.5 用 `AppDatabase` 打开任意文件 → drift 按 `onCreate` 把七张表建出来

- **现象**：测试里想造一个「不是 WorthTrack 的 SQLite 库」（只含一张 `foo` 表）来验证 `missingTables`，结果校验直接通过。
- **根因**：`AppDatabase(NativeDatabase(file))` 打开空库时 `user_version = 0`，drift 判定为「新库」→ 执行 `onCreate: createAll()`，于是七张表被自动补齐。
- **解决**：造「外星库」改用主连接 `ATTACH DATABASE '<path>' AS alien` + `CREATE TABLE alien.foo (...)` + `DETACH`，绕开 drift 的迁移逻辑。
- **预防**：测试里凡是要「一个结构不完整/不正确的库」，一律用 ATTACH 手工建，不要经过 `AppDatabase`。

### 3.6 快照断言里写 `'${row?.field}'` → 空表也「不空」

- **现象**：清空全表后 `expect(await snapshot(db), isEmpty)` 失败，实际值是 `['null@null']`。
- **根因**：`snapshot()` 里有一行 `'${price?.priceMinor}@${price?.updatedAt}'`，price 为 null 时这行仍然生成一个字符串元素，集合永远不为空。
- **解决**：改用集合的 if 元素：`if (price != null) '${price.priceMinor}@${price.updatedAt}'`。
- **预防**：写「快照/摘要」这类对比辅助函数时，每个元素都要能被数据的存在性整体裁掉；否则「空」这个状态根本表达不出来。

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
| 备份/恢复 | 导出 `VACUUM INTO`、恢复 `ATTACH` + 单事务替换（见 2.11–2.13） |
| WSL 命令 | `MSYS_NO_PATHCONV=1`；复杂命令写 scripts/ 脚本 |
| 敏感信息 | 永不命令行内联，脚本内读文件 |
| 发版 | tag `vX.Y.Z` → CI 全绿 → 签名 APK + Linux 包自动上 Release |
