#!/usr/bin/env python3
"""Create WorthTrack v2.0 (M5-M8) GitHub issues from docs/issues-backlog.md.

Idempotent: fetches every existing issue (open + closed) first and skips any
title that already exists, so re-running never duplicates issues.

Token: ~/.config/worthtrack/gh_token
Usage (inside WSL): python3 scripts/create_issues_v2.py [--dry-run]
"""
import json
import os
import sys
import urllib.error
import urllib.request

TOKEN = open(os.path.expanduser("~/.config/worthtrack/gh_token")).read().strip()
REPO = "zeek-zhao/WorthTrack"

DRY = "--dry-run" in sys.argv


def api(path, data=None, method="GET"):
    req = urllib.request.Request(
        f"https://api.github.com{path}",
        data=json.dumps(data).encode() if data else None,
        method=method,
        headers={
            "Authorization": f"Bearer {TOKEN}",
            "Accept": "application/vnd.github+json",
        },
    )
    try:
        with urllib.request.urlopen(req) as r:
            return json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        body = e.read().decode()[:300]
        print(f"ERR {method} {path}: {e.code} {body}")
        return None


def existing_titles():
    titles, page = set(), 1
    while True:
        batch = api(f"/repos/{REPO}/issues?state=all&per_page=100&page={page}")
        if not batch:
            break
        for it in batch:
            if "pull_request" not in it:
                titles.add(it["title"].strip())
        if len(batch) < 100:
            break
        page += 1
    return titles


LABELS = [
    ("M5", "5319E7", "M5 模块化骨架"),
    ("M6", "006B75", "M6 记事本"),
    ("M7", "BFD4F2", "M7 关注与提醒"),
    ("M8", "FBCA04", "M8 游戏与发版"),
]

tpl = lambda checks: "\n".join(f"- [ ] {c}" for c in checks)

ISSUES = [
    # ---------------- M5 模块化骨架（纯重构，零功能变化） ----------------
    (
        "[M5] refactor: 抽出 core 共享内核与 AppModule 契约",
        ["M5"],
        "## 任务\n"
        "- `lib/core/` 收纳 money / stream_utils / 通用组件 / 路由壳\n"
        "- 定义 `AppModule` 与 `ModuleContext`（契约见 wiki《需求规格-v2.0》§3.1）\n"
        "- 静态 `const modules = [...]` 注册表，不引入 build_runner 生成\n"
        "- 模块只经 `ModuleContext` 取 DB / 仓储 / 日志\n\n"
        "## 验收标准\n"
        + tpl(
            [
                "契约字段齐：id / name / icon / defaultOrder / dependsOn / ownedTables / routes / settingsTiles / onEnable / onDisable / onClear",
                "全仓 grep 确认无模块 import `di.dart`",
                "`AppModule` 契约有文档注释，说明每个字段的语义与调用时机",
                "此提交为纯新增，不改变任何现有行为（测试数不变）",
            ]
        )
        + "\n\n## 依赖\n无（M5 起点）",
    ),
    (
        "[M5] refactor: finance 模块整体迁入 lib/modules/finance/",
        ["M5"],
        "## 任务\n"
        "- `git mv` 保留历史，把现有 finance 相关代码整体迁入 `lib/modules/finance/{domain,data,ui}/`\n"
        "- 仅改 import 路径，不改任何逻辑\n\n"
        "## 验收标准\n"
        + tpl(
            [
                "**测试数与迁移前精确相等（299）**",
                "该提交内不得出现 `feat:` 前缀（纯重构）",
                "`dart format` / `flutter analyze --fatal-warnings` / `flutter test` 三关全绿",
                "`git log --follow` 能追溯到搬迁前历史",
            ]
        )
        + "\n\n## 依赖\ncore 与 AppModule 契约（上一条）",
    ),
    (
        "[M5] feat: schema v2 —— module_state 表与首次 onUpgrade",
        ["M5"],
        "## 任务\n"
        "- 本项目**第一次写 migration**：`schemaVersion` 1 → 2，禁止凭记忆写，先查 Drift `Migrator.createTable` 正确姿势\n"
        "- `module_state`：模块 id / 是否启用 / launcher 排序 / 首次启用时间（core 拥有，**必须随备份走**）\n"
        "- migration 收敛为各模块提供的 `MigrationStep` 列表\n\n"
        "## 验收标准\n"
        + tpl(
            [
                "迁移测试：造 v1 库（复用 `test/helpers/sqlite3_loader.dart`）→ 升级到 v2 → 逐表比对数据无损",
                "v1 库中已有的 7 张表数据条数、内容完全一致",
                "新库直接建 v2 与 v1 升级到 v2 的 schema 一致",
                "备份 → 恢复后 `module_state` 与恢复前一致",
            ]
        )
        + "\n\n## 依赖\nfinance 搬迁完成",
    ),
    (
        "[M5] feat: launcher 首页与 go_router 导航",
        ["M5"],
        "## 任务\n"
        "- `go_router` + `StatefulShellRoute.indexedStack`，每模块一个 branch，各自独立返回栈\n"
        "- launcher：模块九宫格 + 常驻「记一笔 / 记一条」两个全局快捷动作\n"
        "- 冷启动恢复上次模块，超过 30 分钟未使用回 launcher\n"
        "- ⚠️ 这是对 `home_page.dart` 五个硬编码 tab 的破坏性重构\n\n"
        "## 验收标准\n"
        + tpl(
            [
                "每个模块有独立返回栈（在 A 模块进二级页，切到 B 再切回 A，仍停在二级页）",
                "冷启动恢复到上次模块；模拟 30 分钟以上未使用则回 launcher",
                "「记一笔」始终 1 步可达（不经过 launcher 二级）",
                "停用某模块后该 branch 不注册，无空 tab、无死链",
            ]
        )
        + "\n\n## 依赖\nschema v2（模块开关状态来源）",
    ),
    (
        "[M5] feat: 模块管理页与设置页拆分",
        ["M5"],
        "## 任务\n"
        "- 设置页拆成 **core 系统设置**（PIN / 整库备份恢复 / 模块管理）+ 各模块 `settingsTiles` 贡献的条目\n"
        "- 模块管理页四个动作：启用 / 停用 / 清理数据 / 排序\n"
        "- 「停用」与「清理」必须是两个独立入口\n\n"
        "## 验收标准\n"
        + tpl(
            [
                "**硬约束：停用 finance 后仍能进入模块管理页重新启用（防死锁）**",
                "停用只隐藏、一行数据不动；清理需二次确认并告知将删除多少条记录",
                "清理只删该模块 `ownedTables` 的数据，不波及他人表",
                "排序结果持久化到 `module_state`",
                "三条路径（启用 / 停用 / 清理）各有 Widget 测试",
            ]
        )
        + "\n\n## 依赖\nlauncher 与 go_router 导航",
    ),
    (
        "[M5] test: 架构测试守住模块边界",
        ["M5"],
        "## 任务\n"
        "- 扫描 `lib/modules/**` 的 import 与表引用，按 `ownedTables` 校验边界\n\n"
        "## 验收标准\n"
        + tpl(
            [
                "禁止跨模块直接访问他人表（按 `ownedTables` 校验）",
                "禁止模块 import `di.dart` / 他人 DAO",
                "`ownedTables` 与 `@DriftDatabase(tables:)` 中的真实表一一对应（双向校验）",
                "故意违规时测试能红（自检用例）",
            ]
        )
        + "\n\n## 依赖\n前五条全部完成（M5 收口）",
    ),
    # ---------------- M6 记事本 ----------------
    (
        "[M6] feat: notes 表 + DAO + 仓储",
        ["M6"],
        "## 任务\n"
        "- `notes` 表：标题 / 正文 / 置顶 / `refType` / `refId` / 时间戳\n"
        "- DAO 必须注册进 `@DriftDatabase(daos:)`，否则 `.g.dart` 静默不生成 getter\n\n"
        "## 验收标准\n"
        + tpl(
            [
                "CRUD 单测；按更新时间排序、置顶优先",
                "搜索命中标题与正文",
                "`refType` + `refId` 存字符串，**不建外键**",
                "schema 变更走 v2 之后的 migration 步骤，有迁移测试",
            ]
        )
        + "\n\n## 依赖\nM5 全部完成",
    ),
    (
        "[M6] feat: 记事本页（列表 / 编辑 / 置顶 / 搜索）",
        ["M6"],
        "## 任务\n"
        "- 纯文本 + 轻量 Markdown（粗体 / 列表 / 标题三件套，自研渲染，不引 `flutter_markdown`）\n"
        "- 列表、编辑、置顶、搜索（标题 + 正文）\n\n"
        "## 验收标准\n"
        + tpl(
            [
                "写一条 → 列表可见 → 编辑生效 → 置顶排序正确",
                "Markdown 三件套渲染正确（粗体 / 列表 / 标题）",
                "空态有新建入口",
                "Widget 测试覆盖上述路径",
            ]
        )
        + "\n\n## 依赖\nnotes 表 + 仓储",
    ),
    (
        "[M6] feat: 弱引用——从标的或账户跳到相关笔记",
        ["M6"],
        "## 任务\n"
        "- 给某只标的或某个账户挂笔记，存 `refType` + `refId`\n"
        "- 从持仓 / 账户页可跳到相关笔记列表\n\n"
        "## 验收标准\n"
        + tpl(
            [
                "从标的详情跳到其关联笔记，只显示该标的的笔记",
                "标的被删或模块停用后，笔记本身仍可读（无外键、不级联）",
                "`refId` 指向不存在对象时静默降级，不崩溃",
            ]
        )
        + "\n\n## 依赖\n记事本页",
    ),
    (
        "[M6] test: 模块停用/清理对 notes 数据的正确性",
        ["M6"],
        "## 验收标准\n"
        + tpl(
            [
                "停用 notes → 入口消失、数据仍在；重新启用后笔记完整",
                "清理 notes → 只删 notes 表，finance 数据一行不动",
                "清理时二次确认文案包含将删除的记录条数",
            ]
        )
        + "\n\n## 依赖\n模块管理页（M5）",
    ),
    # ---------------- M7 关注与提醒 ----------------
    (
        "[M7] feat: watchlist_items 表 + 自选列表",
        ["M7"],
        "## 任务\n"
        "- `watchlist_items`：代码 / 名称 / 是否显示持仓 / 目标价上下限 / 涨跌幅阈值\n"
        "- 已有持仓自动并入，可单独隐藏（同一 `code` 合并为一条，来源标记 `held` / `manual`）\n\n"
        "## 验收标准\n"
        + tpl(
            [
                "手动加 A 股 / 场内基金代码，展示现价、涨跌幅、更新时间",
                "持仓自动并入且默认显示；隐藏后不影响持仓本身",
                "同一代码不重复出现（去重口径：按 `code` 合并）",
                "刷新失败回退缓存价并标注时间",
            ]
        )
        + "\n\n## 依赖\nM5 全部完成；复用 finance 的 PriceProvider",
    ),
    (
        "[M7] feat: 阈值提醒——前台轮询 + 应用内提醒条",
        ["M7"],
        "## 任务\n"
        "- 目标价上穿 / 下穿、涨跌幅超 N%\n"
        "- **仅前台轮询**（默认 30 秒，可关），命中弹应用内提醒条；每次冷启动补检查一次\n"
        "- 明确不做：后台常驻、系统通知、服务端推送\n\n"
        "## 验收标准\n"
        + tpl(
            [
                "上穿 / 下穿 / 涨跌幅三类阈值各有用例",
                "去重口径：同一标的同一阈值当日只提醒一次",
                "断网时静默降级，不弹错误、不崩溃",
                "App 退到后台即停止轮询（前台约束可验证）",
            ]
        )
        + "\n\n## 依赖\n自选列表",
    ),
    (
        "[M7] test: 提醒去重与断网降级",
        ["M7"],
        "## 验收标准\n"
        + tpl(
            [
                "同日重复命中只提醒一次；跨日重新提醒",
                "断网 / 接口限流 / 返回空数据三种降级路径各有用例",
                "轮询间隔可关闭后不再发起请求",
            ]
        )
        + "\n\n## 依赖\n阈值提醒",
    ),
    # ---------------- M8 游戏与发版 ----------------
    (
        "[M8] feat: game 模块——一个最小离线小游戏",
        ["M8"],
        "## 任务\n"
        "- **一个**纯离线小游戏，无网络、无资源包、无内购、无排行榜\n"
        "- 标准：单文件可读完；目的是验证「加模块 = 加目录 + 注册一行」\n"
        "- 候选：2048 或扫雷\n\n"
        "## 验收标准\n"
        + tpl(
            [
                "可完整玩一局，状态机无死锁",
                "无新增第三方依赖、无资源包",
                "停用 / 启用 / 清理三条路径对该模块同样成立",
                "新增代码体积 ≤ 5MB",
            ]
        )
        + "\n\n## 依赖\nM5 全部完成",
    ),
    (
        "[M8] test: 新增模块成本验证",
        ["M8"],
        "## 验收标准\n"
        + tpl(
            [
                "新增 game 模块只允许改注册表一行 + 新增一个目录（用 diff 证明）",
                "架构测试对 game 同样生效（无跨模块访问）",
                "新增模块后全量测试仍全绿，碰钱路径集成测试数量不减",
            ]
        )
        + "\n\n## 依赖\ngame 模块",
    ),
    (
        "[M8] docs: 用户手册与真机手测清单更新、v2.0.0 发版说明",
        ["M8"],
        "## 任务\n"
        "- wiki《用户手册》《真机手测清单》更新到 v2.0 范围\n"
        "- 发版说明按 `docs/release-notes-template.md` 写\n\n"
        "## 验收标准\n"
        + tpl(
            [
                "真机手测清单逐项执行并通过（含 v1.0 遗留项）",
                "用户手册覆盖 4 个模块与模块管理页",
                "Release 存在 v2.0.0（签名 APK + Linux 包）",
                "产品文案写明「打开 App 才提醒」，不暗示后台推送",
            ]
        )
        + "\n\n## 依赖\nM6 / M7 / M8 功能完成",
    ),
]


def main():
    print(f"{'DRY RUN' if DRY else 'LIVE'} · repo {REPO}")
    for name, color, desc in LABELS:
        if not DRY:
            api(f"/repos/{REPO}/labels", {"name": name, "color": color, "description": desc}, "POST")
    print(f"labels ensured: {[n for n, _, _ in LABELS]}")

    have = existing_titles()
    print(f"existing issues: {len(have)}")

    created, skipped = [], []
    for title, labels, body in ISSUES:
        if title in have:
            skipped.append(title)
            print(f"SKIP  {title}")
            continue
        if DRY:
            created.append(title)
            print(f"WOULD {title}")
            continue
        r = api(f"/repos/{REPO}/issues", {"title": title, "body": body, "labels": labels}, "POST")
        if r:
            created.append(f"#{r['number']} {title}")
            print(f"OK    #{r['number']} {title}")
        else:
            print(f"FAIL  {title}")

    print(f"\ncreated {len(created)} · skipped {len(skipped)} · total {len(ISSUES)}")


if __name__ == "__main__":
    main()
