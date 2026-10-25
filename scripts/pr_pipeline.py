#!/usr/bin/env python3
"""通用 PR 流水线：建 PR -> 轮询 CI -> 绿了自动合并 -> 确认 issue 关闭。

用法: python3 pr_pipeline.py <branch> <issue_no> <pr_title> <pr_body_file>
pr_body_file 省略时用默认模板。
"""
import json
import sys
import time
import urllib.request

TOKEN = open("/home/zeek.zhao/.config/worthtrack/gh_token").read().strip()
BASE = "https://api.github.com/repos/zeek-zhao/WorthTrack"
H = {"Authorization": "Bearer " + TOKEN, "Accept": "application/vnd.github+json"}


def call(p, data=None, method="GET"):
    req = urllib.request.Request(
        BASE + p,
        data=json.dumps(data).encode() if data is not None else None,
        method=method,
        headers=H,
    )
    return json.loads(urllib.request.urlopen(req).read().decode())


def main():
    branch, issue = sys.argv[1], int(sys.argv[2])
    title = sys.argv[3]
    try:
        body = open(sys.argv[4]).read()
    except IndexError:
        body = "Closes #%d\n\n见提交记录。" % issue

    pr = call("/pulls", {"title": title, "head": branch, "base": "main", "body": body}, "POST")
    n = pr.get("number")
    print("pr:", n, pr.get("message", "created"), flush=True)
    if n is None:
        sys.exit(1)

    for i in range(40):
        time.sleep(20)
        r = call("/actions/runs?branch=%s&per_page=1" % branch)["workflow_runs"][0]
        print(i, r["head_sha"][:7], r["status"], r["conclusion"], flush=True)
        if r["status"] == "completed":
            if r["conclusion"] == "success":
                m = call("/pulls/%d/merge" % n, {"merge_method": "merge"}, "PUT")
                print("merge:", m.get("merged"), m.get("message", ""), flush=True)
                time.sleep(5)
                print("issue%d:" % issue, call("/issues/%d" % issue)["state"], flush=True)
            else:
                print("CI FAILED on", branch, flush=True)
            break


if __name__ == "__main__":
    main()
