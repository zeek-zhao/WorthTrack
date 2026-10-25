#!/usr/bin/env python3
"""Create WorthTrack GitHub issues from backlog. Token: ~/.config/worthtrack/gh_token"""
import json
import os
import urllib.request

TOKEN = open(os.path.expanduser("~/.config/worthtrack/gh_token")).read().strip()
REPO = "zeek-zhao/WorthTrack"
API = f"https://api.github.com/repos/{REPO}"


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
        print(f"ERR {method} {path}: {e.code} {e.read().decode()[:200]}")
        return None


LABELS = [
    ("M1", "0E8A16", "M1 记账核心"),
    ("M2", "1D76DB", "M2 报表与预算"),
    ("M3", "F9D0C4", "M3 投资跟踪"),
    ("M4", "D93F0B", "M4 备份与打磨"),
]
for name, color, desc in LABELS:
    api(f"/repos/{REPO}/labels", {"name": name, "color": color, "description": desc}, "POST")
print("labels done")

tpl = lambda checks: "\n".join(f"- [ ] {c}" for c in checks)

ISSUES = [
 ("[M1] chore: WSL Ubuntu 24.04 Flutter 开发环境搭建", ["M1"],
  "## 目标\n在 WSL Ubuntu 24.04 搭建 Flutter 开发环境，M1 一切开发的前提。\n\n## 验收标准\n" + tpl([
   "Flutter SDK stable 安装并配 PATH（~/development/flutter）",
   "JDK 17、Android SDK cmdline-tools/platform-tools 就绪，licenses 已接受",
   "flutter doctor -v 无 error（iOS/Chrome 可选项除外）",
   "flutter create 冒烟项目 build apk --debug 成功",
   "环境步骤写入 wiki《WSL 开发环境》"])),
 ("[M1] feat: Flutter 项目脚手架初始化", ["M1"],
  "## 任务\n- flutter create worthtrack（org com.zeekzhao.worthtrack），Android + linux/windows 目标\n- 依赖：Riverpod / Drift / intl / fl_chart\n- 目录骨架 lib/ui lib/repository lib/data；Material 3 主题；默认中文\n\n## 验收标准\n" + tpl([
   "flutter test 冒烟通过", "flutter analyze 无 warning"])),
 ("[M1] ci: CI 三关在真实项目上跑通", ["M1"],
  "## 验收标准\n" + tpl([
   "push 到 main 触发 quality job 且三关绿",
   "PR 分支上 CI 状态检查生效",
   "main 开启分支保护（CI 必须通过才可合并）"])),
 ("[M1] feat: Drift 数据模型与 Migration 基建", ["M1"],
  "## 任务\n- accounts/transactions/categories/budgets/recurring_rules/positions/price_cache 七表\n- 金额整数存「分」；Migration 从 v1 起\n- Repository 接口 + DAO 实现\n\n## 验收标准\n" + tpl([
   "金额分↔元转换单测", "开库/迁移单测", "查询流（Watch）单测"])),
 ("[M1] feat: 账户管理", ["M1"],
  "## 任务\n账户 CRUD（现金/银行卡/信用卡/投资账户）、初始余额、余额实时计算（Drift Watch）。\n\n## 验收标准\n" + tpl([
   "余额计算单测", "建账户 Widget 测试"])),
 ("[M1] feat: 交易记录 CRUD 与流水列表", ["M1"],
  "## 任务\n支出/收入/转账录入编辑删除；流水按日分组、按账户/分类筛选；响应式刷新。\n\n## 验收标准\n" + tpl([
   "余额计算单测（记入/转出/跨账户转账）",
   "交易录入 Widget 测试"])),
 ("[M1] feat: 分类管理", ["M1"],
  "## 任务\n收支分类 CRUD、图标、二级分类、预置默认分类集。\n\n## 验收标准\n" + tpl([
   "分类树操作单测"])),
 ("[M1] test: M1 集成测试（碰钱路径）", ["M1"],
  "## 用例\n" + tpl([
   "建账户→记支出→余额变化正确",
   "两账户转账→双方余额正确",
   "删除交易→余额回滚正确"])),
 ("[M2] feat: 月度/年度报表", ["M2"],
  "## 任务\n收支汇总、分类占比饼图、趋势折线（fl_chart）。\n\n## 验收标准\n" + tpl([
   "汇总/分组统计单测", "报表页 Widget 测试"])),
 ("[M2] feat: 月度预算与超支提示", ["M2"],
  "## 验收标准\n" + tpl([
   "预算消耗计算单测（含跨月边界）",
   "超支提示 Widget 测试"])),
 ("[M2] feat: 周期账单", ["M2"],
  "## 任务\n规则 CRUD（日/周/月）；启动时补生成漏掉的周期记账。碰钱路径，集成测试必须覆盖。\n\n## 验收标准\n" + tpl([
   "补生成单测（连漏三期只生成三期不重复）",
   "集成测试：周期账单生成后余额正确"])),
 ("[M2] feat: 流水搜索与筛选", ["M2"],
  "## 验收标准\n" + tpl([
   "关键词/时间/账户/分类组合过滤单测"])),
 ("[M3] feat: 持仓管理", ["M3"],
  "## 任务\n持仓 CRUD（代码/名称/份额/成本价），归属投资账户。\n\n## 验收标准\n" + tpl([
   "市值/盈亏/百分比计算单测"])),
 ("[M3] feat: PriceProvider 行情接入（新浪/腾讯）", ["M3"],
  "## 任务\n抽象 PriceProvider + TencentPriceProvider；A 股/场内基金报价解析；手动批量刷新落 price_cache。\n\n## 验收标准\n" + tpl([
   "响应解析 fixture 单测（正常/停牌/代码不存在）",
   "集成测试（mock HTTP）：刷新后市值更新"])),
 ("[M3] feat: 行情缓存与手动改价兜底", ["M3"],
  "## 验收标准\n" + tpl([
   "拉取失败回退缓存价单测",
   "UI 标注价格更新时间",
   "手动改价后市值即时更新"])),
 ("[M3] feat: 资产总览与净资产曲线", ["M3"],
  "## 验收标准\n" + tpl([
   "现金+储蓄+投资汇总单测",
   "历史净资产曲线渲染"])),
 ("[M3] feat: 应用启动 PIN 锁", ["M3"],
  "## 验收标准\n" + tpl([
   "锁屏解锁流程 Widget 测试",
   "忘记 PIN 重置流程（数据不丢）"])),
 ("[M4] feat: db 一键备份与恢复", ["M4"],
  "## 验收标准\n" + tpl([
   "导出 .db 到用户选择目录",
   "恢复前二次确认",
   "集成测试：备份→清空→恢复→数据一致"])),
 ("[M4] feat: 交易流水 CSV 导出", ["M4"],
  "## 验收标准\n" + tpl([
   "UTF-8 BOM，Excel 直开不乱码",
   "字段：时间/类型/账户/分类/金额/备注",
   "中文与逗号转义单测"])),
 ("[M4] ci: 发布流水线端到端验证", ["M4"],
  "## 任务\n本地生成 keystore；GitHub Secrets：KEYSTORE_BASE64/KEYSTORE_PASSWORD/KEY_ALIAS/KEY_PASSWORD；tag v0.1.0 试发布。\n\n## 验收标准\n" + tpl([
   "Release 产物（签名 APK + Linux 包）可下载并安装成功"])),
 ("[M4] test: 碰钱路径集成测试补齐", ["M4"],
  "## 验收标准\n" + tpl([
   "对照 wiki 验收标准逐条核对全覆盖"])),
 ("[M4] docs: 用户手册与发版说明", ["M4"],
  "## 验收标准\n" + tpl([
   "wiki：《真机手测清单》《用户手册》《WSL 开发环境》"])),
]

created = []
for title, labels, body in ISSUES:
    r = api(f"/repos/{REPO}/issues",
            {"title": title, "body": body, "labels": labels}, "POST")
    if r:
        created.append(f"#{r['number']} {title}")
        print(f"OK #{r['number']} {title}")

print(f"\nTOTAL {len(created)}/{len(ISSUES)}")
