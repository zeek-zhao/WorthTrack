#!/usr/bin/env python3
"""拉取指定 commit 最新 check run 的失败日志片段。用法: python3 ci_log.py <sha>"""
import json
import sys
import urllib.request

TOKEN = open("/home/zeek.zhao/.config/worthtrack/gh_token").read().strip()
BASE = "https://api.github.com/repos/zeek-zhao/WorthTrack"
H = {"Authorization": "Bearer " + TOKEN, "Accept": "application/vnd.github+json"}

sha = sys.argv[1]
req = urllib.request.Request(BASE + f"/commits/{sha}/check-runs", headers=H)
runs = json.loads(urllib.request.urlopen(req).read().decode())
for c in runs["check_runs"]:
    if c["conclusion"] not in (None, "success", "skipped"):
        print("== FAILED:", c["name"], c["conclusion"], "job", c["id"])
        lreq = urllib.request.Request(
            BASE + f"/actions/jobs/{c['id']}/logs", headers=H
        )
        try:
            # 禁自动重定向：日志接口 302 到 blob，重定向不能带 token。
            class NoRedirect(urllib.request.HTTPRedirectHandler):
                def redirect_request(self, *a, **k):
                    return None

            opener = urllib.request.build_opener(NoRedirect)
            try:
                resp = opener.open(lreq)
                log = resp.read().decode("utf-8", "replace")
            except urllib.error.HTTPError as e2:
                if e2.status in (301, 302, 303, 307):
                    rreq = urllib.request.Request(
                        e2.headers["Location"],
                        headers={"Accept": "text/plain"},
                    )
                    log = urllib.request.urlopen(rreq).read().decode(
                        "utf-8", "replace"
                    )
                else:
                    raise
        except Exception as e:
            print("log fetch error:", e)
            continue
        lines = log.splitlines()
        for i, l in enumerate(lines):
            low = l.lower()
            if any(
                k in low
                for k in (
                    "##[error]",
                    "error:",
                    "failed",
                    "some tests failed",
                    "expected",
                    "actual",
                )
            ):
                print("\n".join(lines[max(0, i - 2) : i + 8]))
                print("-----")
