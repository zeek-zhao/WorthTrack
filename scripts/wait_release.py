#!/usr/bin/env python3
"""等待某个 tag 的发布流水线跑完，并核对 Release 产物。

用法：python3 scripts/wait_release.py v0.4.0 [超时分钟，默认 40]

为什么不用 poll_release.py：那个脚本把 tag 写死成 v0.1.0，只够一次性用。
"""
import json
import sys
import time
import urllib.error
import urllib.request

TAG = sys.argv[1] if len(sys.argv) > 1 else ""
TIMEOUT_MIN = int(sys.argv[2]) if len(sys.argv) > 2 else 40
if not TAG:
    print("usage: wait_release.py <tag> [timeout_minutes]")
    sys.exit(2)

TOKEN = open("/home/zeek.zhao/.config/worthtrack/gh_token").read().strip()
BASE = "https://api.github.com/repos/zeek-zhao/WorthTrack"
HEADERS = {"Authorization": "Bearer " + TOKEN}


def call(path):
    req = urllib.request.Request(BASE + path, headers=HEADERS)
    try:
        return json.loads(urllib.request.urlopen(req).read().decode())
    except urllib.error.HTTPError as e:
        return {"error": e.code, "body": e.read().decode()[:200]}


deadline = time.time() + TIMEOUT_MIN * 60
run = None
while time.time() < deadline:
    runs = call(f"/actions/runs?branch={TAG}&per_page=5").get("workflow_runs", [])
    if runs:
        run = runs[0]
        print(
            f"[{time.strftime('%H:%M:%S')}] run {run['id']} "
            f"{run['status']}/{run['conclusion']}"
        )
        if run["status"] == "completed":
            break
    time.sleep(30)

if not run or run["status"] != "completed":
    print("TIMEOUT")
    sys.exit(1)

if run["conclusion"] != "success":
    print(f"CI FAILED: {run['html_url']}")
    jobs = call(f"/actions/runs/{run['id']}/jobs")
    for job in jobs.get("jobs", []):
        print(f"== {job['name']} [{job['conclusion']}]")
        for step in job.get("steps", []):
            mark = "FAIL" if step["conclusion"] == "failure" else "ok"
            print(f"   {mark:>4} {step['number']}. {step['name']}")
    sys.exit(1)

release = call(f"/releases/tags/{TAG}")
if "error" in release:
    print(f"release not found: {release}")
    sys.exit(1)

print(f"\nRELEASE {release['tag_name']} — {release['html_url']}")
for asset in release.get("assets", []):
    mb = asset["size"] / 1024 / 1024
    print(f"  {asset['name']:<32} {mb:6.1f} MB  downloads={asset['download_count']}")
print(f"  assets={len(release.get('assets', []))}")
