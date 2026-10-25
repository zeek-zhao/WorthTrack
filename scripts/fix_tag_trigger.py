#!/usr/bin/env python3
"""建 PR -> 轮询 CI -> 绿了合并 -> 重打 tag 触发发布。无关联 issue 的 ci 修复专用。"""
import json
import subprocess
import time
import urllib.request

T = open("/home/zeek.zhao/.config/worthtrack/gh_token").read().strip()
BASE = "https://api.github.com/repos/zeek-zhao/WorthTrack"
H = {"Authorization": "Bearer " + T, "Accept": "application/vnd.github+json"}
BRANCH = "ci/tag-trigger"
TAG = "v0.1.0"


def call(p, data=None, method="GET"):
    req = urllib.request.Request(
        BASE + p,
        data=json.dumps(data).encode() if data is not None else None,
        method=method,
        headers=H,
    )
    return json.loads(urllib.request.urlopen(req).read().decode())


pr = call(
    "/pulls",
    {
        "title": "ci: enable tag push trigger for release pipeline",
        "head": BRANCH,
        "base": "main",
        "body": "on.push 只配了 branches，tags 推送不触发任何 run，release job 永远不会执行。补 tags: ['v*']。\n\n不关联 issue（refs #20 发布基建的一部分）。",
    },
    "POST",
)
n = pr["number"]
print("pr:", n, flush=True)

for i in range(30):
    time.sleep(20)
    r = call(f"/actions/runs?branch={BRANCH}&per_page=1")["workflow_runs"][0]
    print(i, r["status"], r["conclusion"], flush=True)
    if r["status"] == "completed":
        if r["conclusion"] == "success":
            m = call(f"/pulls/{n}/merge", {"merge_method": "merge"}, "PUT")
            print("merge:", m.get("merged"), flush=True)
        else:
            print("CI FAILED")
            raise SystemExit(1)
        break

# 等 main 上合并后的 run 存在，然后重打 tag 到新 main 提交
time.sleep(10)
subprocess.run(["git", "fetch", "-q", "origin"], check=True)
new_main = subprocess.run(
    ["git", "rev-parse", "origin/main"], capture_output=True, text=True
).stdout.strip()
print("new main:", new_main, flush=True)

subprocess.run(["git", "tag", "-d", TAG], check=True)
subprocess.run(["git", "push", "-q", f"origin:refs/tags/{TAG}"], check=True)
subprocess.run(
    ["git", "tag", "-a", TAG, new_main, "-m", "WorthTrack v0.1.0 - M1 记账核心"],
    check=True,
)
subprocess.run(["git", "push", "-q", f"origin refs/tags/{TAG}"], check=True)
print("tag re-pushed to", new_main[:7], flush=True)
