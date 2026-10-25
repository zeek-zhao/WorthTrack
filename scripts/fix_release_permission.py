#!/usr/bin/env python3
"""PR(#30 ci/release-permission) -> CI 绿 -> 合并 -> 重打 v0.1.0 tag 到新 main。"""
import json
import subprocess
import time
import urllib.request

T = open("/home/zeek.zhao/.config/worthtrack/gh_token").read().strip()
BASE = "https://api.github.com/repos/zeek-zhao/WorthTrack"
H = {"Authorization": "Bearer " + T, "Accept": "application/vnd.github+json"}
BRANCH = "ci/release-permission"
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
        "title": "ci: grant contents:write to release job",
        "head": BRANCH,
        "base": "main",
        "body": "默认 GITHUB_TOKEN 无 contents 写权限，Create GitHub Release 403（refs #20）。",
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

time.sleep(10)
subprocess.run(["git", "fetch", "-q", "origin"], check=True)
new_main = subprocess.run(
    ["git", "rev-parse", "origin/main"], capture_output=True, text=True
).stdout.strip()
subprocess.run(["git", "push", "-q", "origin", "--delete", TAG], check=True)
subprocess.run(["git", "tag", "-f", "-a", TAG, new_main, "-m", "WorthTrack v0.1.0 - M1 记账核心"], check=True)
subprocess.run(["git", "push", "-q", "origin", f"refs/tags/{TAG}"], check=True)
print("tag re-pushed to", new_main[:7], flush=True)
