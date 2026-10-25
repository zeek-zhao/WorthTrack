# WorthTrack

跨平台记账 + 理财应用。Flutter + Riverpod + Drift(SQLite)，数据 100% 本地。

- 需求规格与项目计划：见 [Wiki](https://github.com/zeek-zhao/WorthTrack/wiki)
- 开发环境：WSL Ubuntu 24.04 → push GitHub → Actions CI → Release 下载安装

## 技术栈

| 层 | 选型 |
|---|---|
| 框架 | Flutter（Android 优先，Linux/Windows 桌面可用） |
| 状态管理 | Riverpod |
| 存储 | Drift + SQLite（金额整数存「分」） |
| 行情 | 新浪/腾讯财经公开接口（仅 A 股 + 场内基金），缓存价 + 手动兜底 |

## 开发约定

- 分支：`main` + `feat/*`；PR 过 CI（format/analyze/test）才可合并
- 提交：Conventional Commits（feat/fix/docs/refactor/test）
- AI 改动记录：`docs/ai-changelog.md`（每次 AI 会话：任务/文件/理由/验证）
- issue 标签分组：M1 记账核心 / M2 报表与预算 / M3 投资跟踪 / M4 备份与打磨

## 构建

```bash
flutter pub get
flutter test          # 单元 + Widget 测试
flutter test integration_test  # 碰钱路径集成测试
flutter build apk --release
```
