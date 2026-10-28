#!/usr/bin/env bash
# 查询当前仓库的 open PR（排查 pr_pipeline 是否已建过 PR 用）
set -euo pipefail
TOKEN=$(cat "$HOME/.config/worthtrack/gh_token")
curl -s -H "Authorization: token $TOKEN" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/zeek-zhao/WorthTrack/pulls?state=open&per_page=20" \
  | python3 -c "import sys,json;d=json.load(sys.stdin);[print(p['number'], p['head']['ref'], p['title']) for p in d] if isinstance(d,list) else print(d)"
