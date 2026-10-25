#!/usr/bin/env python3
"""Create PR for feat/drift-schema, poll CI, merge when green."""
import json
import time
import urllib.request

TOKEN = open('/home/zeek.zhao/.config/worthtrack/gh_token').read().strip()
BASE = 'https://api.github.com/repos/zeek-zhao/WorthTrack'
HEADERS = {'Authorization': 'Bearer ' + TOKEN,
           'Accept': 'application/vnd.github+json'}


def call(path, data=None, method='GET'):
    req = urllib.request.Request(
        BASE + path,
        data=json.dumps(data).encode() if data is not None else None,
        method=method, headers=HEADERS)
    return json.loads(urllib.request.urlopen(req).read().decode())


body = """Closes #4

## 内容
- 七表 schema：accounts / categories / transactions / budgets / recurring_rules / positions / price_cache
- 金额全部整数存「分」；Money 工具类（parseYuan / toYuan）+ 往返一致性单测
- AccountDao / TransactionDao（@DriftAccessor + mixin）：记账与余额调整同一事务原子完成
- AccountRepository / TransactionRepository 接口 + Drift 实现
- 约束：持仓 (market, code) 唯一、预算 (category, month) 唯一、价格缓存 symbol 主键 upsert

## 测试（29 项全绿）
- 金额分↔元转换（含非法输入、负数、往返一致性）
- 开库/迁移：schema v1 七表、文件库重开数据仍在、枚举 int 存取
- 碰钱路径：支出/收入/转账余额流转、transfer 缺参校验、事务回滚不落库
- Watch 流：账户新增推送、归档过滤、按月过滤（左闭右开）、倒序

## 备注
- 枚举+表+库保持单文件：drift_dev 2.29–2.31（Dart 3.9 上限）跨文件布局会静默丢弃 intEnum 列（已最小复现），待 Dart ≥3.10 后再拆
- 新增 test helper：WSL 无系统 libsqlite3 时回退 ~/.local/lib/libsqlite3.so（scripts/setup_sqlite3_local.sh）

## 自查
- [x] dart format --set-exit-if-changed 通过
- [x] flutter analyze 无 issue
- [x] flutter test 29/29 通过"""

pr = call('/pulls', {
    'title': 'feat: Drift 数据模型与 Migration 基建（七表 + 金额存分 + Repo/DAO）',
    'head': 'feat/drift-schema', 'base': 'main', 'body': body,
}, 'POST')
print('PR:', pr.get('number'), pr.get('html_url', pr.get('message')))
num = pr['number']

# 轮询 CI
for i in range(40):
    time.sleep(20)
    runs = call('/actions/runs?branch=feat/drift-schema&per_page=1')
    if not runs['workflow_runs']:
        print(i, 'no run yet')
        continue
    r = runs['workflow_runs'][0]
    print(i, r['status'], r['conclusion'])
    if r['status'] == 'completed':
        if r['conclusion'] == 'success':
            m = call('/pulls/%d/merge' % num, {'merge_method': 'merge'}, 'PUT')
            print('merge:', m.get('merged'), m.get('message', ''))
        else:
            print('CI FAILED, not merging')
        break
