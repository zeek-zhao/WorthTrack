#!/usr/bin/env python3
"""轮询指定 PR 的 CI 状态，全绿自动 merge。用法: python3 poll_pr.py <pr_no> [timeout_sec]"""
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
    pr_no = int(sys.argv[1])
    deadline = time.time() + int(sys.argv[2]) if len(sys.argv) > 2 else time.time() + 1800
    sha = call(f"/pulls/{pr_no}")["head"]["sha"]
    while time.time() < deadline:
        runs = call(f"/commits/{sha}/check-runs")
        checks = runs.get("check_runs", [])
        if checks:
            done = [c for c in checks if c["status"] == "completed"]
            print(
                f"[{time.strftime('%H:%M:%S')}] {len(done)}/{len(checks)} done: "
                + ", ".join(f"{c['name']}={c['conclusion'] or c['status']}" for c in checks),
                flush=True,
            )
            if len(done) == len(checks):
                if all(c["conclusion"] in ("success", "skipped") for c in checks):
                    call(
                        f"/pulls/{pr_no}/merge",
                        {"merge_method": "merge", "sha": sha},
                        "PUT",
                    )
                    print("MERGED", flush=True)
                    return
                print("CI FAILED", flush=True)
                sys.exit(1)
        else:
            print("no check runs yet", flush=True)
        time.sleep(30)
    print("TIMEOUT", flush=True)
    sys.exit(2)


if __name__ == "__main__":
    main()
