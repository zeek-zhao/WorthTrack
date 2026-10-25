#!/usr/bin/env python3
"""下载指定 run 的指定步骤日志片段。用法: step_log.py <run_id> <step名子串>"""
import json
import sys
import urllib.request

T = open("/home/zeek.zhao/.config/worthtrack/gh_token").read().strip()
BASE = "https://api.github.com/repos/zeek-zhao/WorthTrack"
H = {"Authorization": "Bearer " + T}

run_id, needle = sys.argv[1], sys.argv[2]


def get(p, raw=False):
    req = urllib.request.Request(BASE + p, headers=H)
    resp = urllib.request.urlopen(req)
    return resp.read() if raw else json.loads(resp.read().decode())


jobs = get(f"/actions/runs/{run_id}/jobs")["jobs"]
for j in jobs:
    for s in j["steps"]:
        if needle.lower() in s["name"].lower():
            # job logs 端点重定向到日志文件
            req = urllib.request.Request(BASE + f"/actions/jobs/{j['id']}/logs", headers=H)

            class NoRedirect(urllib.request.HTTPRedirectHandler):
                def redirect_request(self, *a, **k):
                    return None

            opener = urllib.request.build_opener(NoRedirect)
            try:
                opener.open(req)
            except urllib.error.HTTPError as e:
                url = e.headers["Location"]
            else:
                url = req.get_full_url()
            log = urllib.request.urlopen(url).read().decode(errors="replace")
            lines = log.splitlines()
            hit = [i for i, l in enumerate(lines) if "FAIL" in l.upper() or "Error" in l or "Exception" in l]
            shown = set()
            for i in hit:
                for k in range(max(0, i - 2), min(len(lines), i + 4)):
                    if k not in shown:
                        print(lines[k])
                        shown.add(k)
            if not hit:
                print("\n".join(lines[-40:]))
