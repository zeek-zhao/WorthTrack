#!/usr/bin/env python3
"""临时脚本：拉取指定 issue 正文，供开发参考。"""
import json
import sys
import urllib.request
from pathlib import Path

TOKEN = Path.home() / ".config/worthtrack/gh_token"


def fetch(n: int) -> dict:
    req = urllib.request.Request(
        f"https://api.github.com/repos/zeek-zhao/WorthTrack/issues/{n}",
        headers={"Authorization": f"token {TOKEN.read_text().strip()}"},
    )
    with urllib.request.urlopen(req) as r:
        return json.load(r)


for n in sys.argv[1:]:
    d = fetch(int(n))
    body = d.get("body") or ""
    print(f"== #{d['number']} {d['title']} [state={d['state']}]")
    print(body[:1500])
    print()
