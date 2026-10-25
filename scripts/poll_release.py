#!/usr/bin/env python3
"""轮询 v0.1.0 发布流水线直至完成，成功则输出 Release 与产物清单。"""
import json
import time
import urllib.request

T = open("/home/zeek.zhao/.config/worthtrack/gh_token").read().strip()
BASE = "https://api.github.com/repos/zeek-zhao/WorthTrack"
H = {"Authorization": "Bearer " + T}


def call(p):
    r = urllib.request.Request(BASE + p, headers=H)
    return json.loads(urllib.request.urlopen(r).read().decode())


for i in range(60):
    time.sleep(30)
    runs = call("/actions/runs?per_page=5")["workflow_runs"]
    tag_runs = [x for x in runs if x["head_branch"] == "v0.1.0"]
    if not tag_runs:
        print(i, "waiting for tag run...", flush=True)
        continue
    r = tag_runs[0]
    print(i, r["head_sha"][:7], r["status"], r["conclusion"], flush=True)
    if r["status"] == "completed":
        jobs = call(f"/actions/runs/{r['id']}/jobs")
        for j in jobs["jobs"]:
            print("job:", j["name"], j["conclusion"], flush=True)
            for s in j["steps"]:
                if s["conclusion"] not in ("success", "skipped", None):
                    print("  FAILED step:", s["name"], flush=True)
        if r["conclusion"] == "success":
            rel = call("/releases/tags/v0.1.0")
            print("release:", rel.get("name"), "|", rel.get("html_url"), flush=True)
            for a in rel.get("assets", []):
                print("  asset:", a["name"], f"{a['size']/1048576:.1f}MB", flush=True)
        break
