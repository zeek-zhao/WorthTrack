#!/usr/bin/env python3
"""查询 v0.1.0 tag 的 CI run 状态与 Release 产物。"""
import json
import urllib.request

T = open("/home/zeek.zhao/.config/worthtrack/gh_token").read().strip()
BASE = "https://api.github.com/repos/zeek-zhao/WorthTrack"
H = {"Authorization": "Bearer " + T}


def call(p):
    r = urllib.request.Request(BASE + p, headers=H)
    return json.loads(urllib.request.urlopen(r).read().decode())


runs = call("/actions/runs?per_page=10")["workflow_runs"]
for r in runs:
    if r["head_branch"] == "v0.1.0":
        print("run:", r["id"], r["status"], r["conclusion"])
        jobs = call(f"/actions/runs/{r['id']}/jobs")
        for j in jobs["jobs"]:
            print(" job:", j["name"], j["status"], j["conclusion"])
            for s in j["steps"]:
                print("  ", s["name"], "->", s["status"], s["conclusion"])
        break
else:
    print("no run for v0.1.0 yet")

rel = call("/releases")
for x in rel:
    print("RELEASE:", x["tag_name"], "|", x["name"], "|", [a["name"] for a in x["assets"]])
