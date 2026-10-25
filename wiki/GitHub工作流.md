<!-- 状态：synced ｜ 来源：Obsidian 40-项目/WorthTrack/WorthTrack-GitHub工作流.md -->

# WorthTrack GitHub 工作流（项目管理交互指南）

本页是 WorthTrack 与 GitHub 交互进行项目管理的操作手册，结合仓库当前实际配置编写。

## 1. 总览

| 项 | 实际值 |
|---|---|
| 仓库 | `github.com/zeek-zhao/WorthTrack`（公开） |
| 默认分支 | `main`（必须 PR 过 CI 才能合入） |
| 工作分支 | `feat/*`（功能）、`fix/*`（修 bug） |
| 看板 | Projects：Todo / In Progress / Done 三列 |
| 里程碑 | M1 记账核心 / M2 报表与预算 / M3 投资跟踪 / M4 备份与打磨 |
| Issue 体系 | `#1-#22` 已建，`[M1]`-`[M4]` 标签分组，feature/bug 两套模板 |
| 发布 | push tag `v*` 触发 Actions：构建签名 APK + Linux 包 → 自动 GitHub Release |

## 2. 日常工作流（一次功能迭代的标准闭环）

```
领 issue（看板 Todo → In Progress）
   ↓
git checkout -b feat/<主题>     ← 从最新 main 切出
   ↓
开发 + 本地三关（format / analyze / test 全绿）
   ↓
commit（Conventional Commits，正文带 refs #N）
   ↓
push 分支 → 开 PR（正文写 Closes #N + 自查清单）
   ↓
CI 三关跑绿 → merge 到 main（issue 自动关闭）
   ↓
看板条目移到 Done，docs/ai-changelog.md 补一条记录
```

**铁律**：
- 任何代码不直接 push `main`。
- PR 必须在 CI 三关全绿后合并，不手动跳过。
- AI 每次会话结束前更新 `docs/ai-changelog.md`。

## 3. Issue 的开与关

**开 issue**：
- 新功能：用 `.github/ISSUE_TEMPLATE/feature.md` 模板，标题 `[M1] feat: 主题`，打对应里程碑标签 + `enhancement`。
- Bug：用 `bug.md` 模板，标题 `[M1] fix: 现象描述`，打 `bug` 标签，正文必须含**复现步骤**和**期望行为**。
- 大功能先在 wiki 需求页对齐再拆 issue；范围变化时先改 Obsidian 草稿 → 同步 wiki → 才允许开工。

**领 issue 与关闭**：
- 开工前：看板条目移到 In Progress。
- 关闭：**优先在 PR 描述写 `Closes #N`**，合并时自动关闭；手动关闭注明 `completed`。
- 未做完不要关；做不完的部分拆新 issue 挂同一里程碑。

## 4. Milestones 与 Projects 看板

**Milestones**（[/milestones](https://github.com/zeek-zhao/WorthTrack/milestones)）：M1(7) / M2(4) / M3(5) / M4(5)。Issue 按标题前缀归属；里程碑 issue 全部关闭后关里程碑并打 tag 发版。

**Projects 看板**（[/projects](https://github.com/zeek-zhao/WorthTrack/projects)）：

| 列 | 放什么 | 移动时机 |
|---|---|---|
| Todo | 已建未开工 | 建 issue 时入列 |
| In Progress | 正在做的 | 开工切分支时 |
| Done | 已合并的 | PR 合并后立即 |

## 5. 分支与提交规范

**分支命名**：功能 `feat/<短主题>`（如 `feat/drift-schema`）；修 bug `fix/<短主题>`。从最新 main 切出；一个分支一个 issue；合并后删远端分支。

**Conventional Commits**：
```
<type>: <一句话说明> (refs #N | closes #N)
```
type ∈ feat / fix / refactor / test / docs / ci / chore / style。只有 PR 收口提交用 `closes`；格式化修正单独 `style:` 提交。

## 6. PR 与 CI

**PR 描述必含**：`Closes #N`、改动要点、自查清单（format / analyze / test 勾选）。

**CI 三关**（`.github/workflows/ci.yml`，Flutter 钉死 3.35.4 与本地一致）：
1. `dart format --output=none --set-exit-if-changed .`
2. `flutter analyze --fatal-infos`
3. `flutter test`

**发布**：push tag `v1.0.0`（语义化版本）→ 构建签名 APK + Linux 包 → 自动 GitHub Release。keystore 不进仓库，密码走 GitHub Secrets。

## 7. AI 改动记录三件套

1. **Conventional Commits**（§5）
2. **`docs/ai-changelog.md`**：每次 AI 会话追加一行——日期、任务、文件、决策理由/踩坑、验证结果
3. **Issue 闭环**：refs/closes 关联 + 看板状态同步

## 8. 本机工具链（当前实际配置）

| 项 | 值 |
|---|---|
| 开发/验证环境 | WSL `Ubuntu-24.04-Zeek`（所有命令类操作在此执行） |
| git 推送 | SSH key（已认证 zeek-zhao） |
| GitHub API | token 在 WSL `~/.config/worthtrack/gh_token`（600），issue/PR/Milestone/Projects 走 REST/GraphQL |
| 工具脚本 | `scripts/create_issues.py`、`set_board_status.py`、`check_ci.py`、`pr_drift_schema.py`（建 PR→轮询 CI→绿了自动合并） |
| Flutter | `~/development/flutter`（3.35.4，Dart 3.9.2）；JDK 17 / Android SDK 用户目录 |
| 已知坑 | wsl.exe 需 `MSYS_NO_PATHCONV=1`；job 级 `if` 不能用 `hashFiles` |

## 9. 常用操作速查

```bash
# 开工
git checkout main && git pull && git checkout -b feat/xxx

# 本地三关
dart format --output=none --set-exit-if-changed .
flutter analyze --fatal-infos
flutter test

# 看板状态移动（WSL）
python3 scripts/set_board_status.py <issue号> "In Progress"   # 或 Done

# CI 失败排查
python3 scripts/check_ci.py
```
