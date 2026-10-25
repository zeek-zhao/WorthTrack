# AI 改动记录（ai-changelog）

> 规则：每次 AI 工作会话必须追加一条。格式：日期 | 任务 | 涉及文件 | 决策理由 | 验证结果。

| 日期 | 任务 | 涉及文件 | 决策理由 | 验证 |
|---|---|---|---|---|
| 2026-10-25 | 项目初始化：README、.gitignore、CI 流水线、PR/issue 模板、issues-backlog、本文件 | README.md, .gitignore, .github/**, docs/** | 按已定稿的项目计划（wiki/项目计划与里程碑）建立工程基建；CI 硬门槛是「保证 AI 代码质量」的核心机制，先于业务代码落地 | 本地 git 提交 + SSH 推送成功；CI workflow 首次跑通待 Flutter 项目落地后确认 |
| 2026-10-25 | 需求规格与项目计划定稿（grill-me 7 分支）| wiki: Home/需求规格-v1.0/项目计划与里程碑/_Sidebar | 记账+A股投资跟踪；Drift+SQLite；Riverpod 三层；CI 硬门槛+碰钱路径集成测试；tag 触发签名 Release | 决策经用户逐项确认 |
