# WorthTrack

跨平台记账 + A 股/场内基金投资跟踪应用。Flutter + Riverpod + Drift(SQLite)，**数据 100% 本地**：
没有账号、没有云端、没有遥测。

- 用户手册：[Wiki / 用户手册](https://github.com/zeek-zhao/WorthTrack/wiki/用户手册)
- 需求规格与项目计划：见 [Wiki](https://github.com/zeek-zhao/WorthTrack/wiki)
- 下载安装：[Releases](https://github.com/zeek-zhao/WorthTrack/releases)（Android APK + Linux 包）
- 开发环境：WSL Ubuntu 24.04 → push GitHub → Actions CI → Release 下载安装

## 功能（v0.4.0）

| 模块 | 能力 |
|---|---|
| 记账 | 支出/收入/转账、多账户（现金/储蓄卡/信用卡/投资）、两级分类、编辑与删除自动回滚余额 |
| 报表 | 月/年收支汇总、分类占比、逐月趋势、流水搜索与组合筛选 |
| 预算 | 分类 × 月份的额度与消耗进度，超支出红色横幅 |
| 周期账单 | 每天/周/月/年规则，启动时补齐漏掉的期数（幂等，月末日期自动收敛） |
| 投资 | A 股 + 场内基金持仓、腾讯行情手动刷新、缓存价兜底、手动改价、盈亏红涨绿跌 |
| 资产 | 净资产（现金类 + 持仓市值）与反向回溯的走势曲线 |
| 安全 | 6 位 PIN 锁（冷启动 + 后台返回重新上锁），凭据独立于数据库 |
| 备份 | 整库导出/恢复（`VACUUM INTO` 快照 + 单事务替换，失败整体回滚） |
| 导出 | 流水 CSV（UTF-8 BOM，Excel 直开不乱码） |

## 技术栈

| 层 | 选型 |
|---|---|
| 框架 | Flutter 3.35.4（Android 优先，Linux/Windows 桌面可用） |
| 状态管理 | Riverpod |
| 存储 | Drift + SQLite（金额整数存「分」，份额 0.01 份） |
| 行情 | 腾讯财经公开接口（仅 A 股 + 场内基金），缓存价 + 手动兜底 |

## 开发约定

- 分支：`main` + `feat/*`；PR 过 CI（format/analyze/test/集成测试）才可合并
- 提交：Conventional Commits（feat/fix/docs/refactor/test），正文带 `Closes #N`
- AI 改动记录：`docs/ai-changelog.md`（每次 AI 会话：任务/文件/理由/验证）
- 踩坑沉淀：`docs/troubleshooting.md`（现象 → 根因 → 解决 → 预防）
- 碰钱路径覆盖：`docs/money-paths-coverage.md`（集成测试 13 条 × 覆盖逻辑）
- issue 标签分组：M1 记账核心 / M2 报表与预算 / M3 投资跟踪 / M4 备份与打磨

## 构建

```bash
flutter pub get
flutter test                    # 单测 + Widget 测试
flutter test integration_test   # 碰钱路径集成测试（Linux 需 clang/cmake/ninja/GTK/xvfb）
flutter build apk --release     # 需要签名配置，见 docs/troubleshooting.md
```

## 发版

`tag vX.Y.Z` → CI 全绿 → 自动创建 Release 并上传签名 APK + Linux 包。
发版说明模板见 `docs/release-notes-template.md`，历史说明在 `docs/release-notes/`。
