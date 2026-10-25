# AI 改动记录（ai-changelog）

> 规则：每次 AI 工作会话必须追加一条。格式：日期 | 任务 | 涉及文件 | 决策理由 | 验证结果。

| 日期 | 任务 | 涉及文件 | 决策理由 | 验证 |
|---|---|---|---|---|
| 2026-10-25 | 项目初始化：README、.gitignore、CI 流水线、PR/issue 模板、issues-backlog、本文件 | README.md, .gitignore, .github/**, docs/** | 按已定稿的项目计划（wiki/项目计划与里程碑）建立工程基建；CI 硬门槛是「保证 AI 代码质量」的核心机制，先于业务代码落地 | 本地 git 提交 + SSH 推送成功；CI workflow 首次跑通待 Flutter 项目落地后确认 |
| 2026-10-25 | 需求规格与项目计划定稿（grill-me 7 分支）| wiki: Home/需求规格-v1.0/项目计划与里程碑/_Sidebar | 记账+A股投资跟踪；Drift+SQLite；Riverpod 三层；CI 硬门槛+碰钱路径集成测试；tag 触发签名 Release | 决策经用户逐项确认 |
| 2026-10-25 | GitHub 工程化：22 条 issue（#1-#22，M1-M4 标签）+ labels 创建；Projects 看板脚本备好（GraphQL createProjectV2 被 403，token 缺 Projects 权限待补）；Flutter SDK 3.35.4 后台下载至 WSL | scripts/create_issues.py, scripts/create_project_board.py | issue 用标签分组代替 Milestone（REST 无 milestone 创建通道）；token 存 WSL ~/.config/worthtrack/gh_token (600) | issues 22/22 创建成功；看板创建失败已定位原因 |
| 2026-10-25 | M1 #1 环境搭建（WSL Ubuntu 24.04-Zeek）：Flutter 3.35.4 + Temurin JDK 17（用户目录免 sudo）+ Android SDK 35.0.0（licenses 全收）；flutter doctor 三绿（Android/Chrome/Network），Linux desktop 工具链待 sudo 装 clang/cmake/ninja（M4 前完成即可） | scripts/setup_wsl_env.sh, scripts/setup_wsl_env2.sh, scripts/smoke_build.sh | JDK 用用户目录安装绕开 sudo 密码；MSYS_NO_PATHCONV=1 解决 wsl.exe 路径转换；WSL PATH 含括号需引号包裹赋值 | flutter doctor ✓；冒烟 APK 构建后台进行中 |
| 2026-10-25 | M1 #1 收尾：冒烟构建成功（app-debug.apk 141MB，5m24s 含首次 Gradle 下载）；wiki 新增《WSL 开发环境》页并推送；关闭 issue #1 | wiki/WSL开发环境.md, scripts/smoke_build.sh | 验收标准全满足：doctor 无 error + 冒烟 APK + 环境文档化 | build apk ✓；issue #1 已关 |
| 2026-10-25 | M1 #2 脚手架：flutter create（android/linux/windows，org com.zeekzhao）+ 依赖 flutter_riverpod/drift/intl/fl_chart + drift_dev/build_runner(dev)；lib 最小骨架 main.dart+app.dart（Material 3 中文）；替换默认计数器测试为应用冒烟测试 | pubspec.yaml, lib/main.dart, lib/app.dart, test/widget_test.dart, android/ linux/ windows/ 脚手架 | 平台只建目标三端，不带 ios/web；UI 结构留到后续 issue（底部导航属 #6 范围） | 本地三关全绿：format 0 变更 / analyze 无问题 / test 1 通过；feat/scaffold 分支待 PR |
