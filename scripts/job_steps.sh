#!/usr/bin/env bash
# 打印某次 CI run 每个 job 的 step 结论（核对集成测试是否真的跑了）
set -euo pipefail
TOKEN=$(cat "$HOME/.config/worthtrack/gh_token")
SHA=${1:-main}
RUN_ID=$(curl -s -H "Authorization: token $TOKEN" \
  "https://api.github.com/repos/zeek-zhao/WorthTrack/actions/runs?head_sha=$SHA&per_page=1" \
  | python3 -c "import sys,json;d=json.load(sys.stdin);print(d['workflow_runs'][0]['id'] if d.get('workflow_runs') else '')")
if [ -z "$RUN_ID" ]; then
  echo "no run for $SHA"
  exit 1
fi
echo "run=$RUN_ID"
curl -s -H "Authorization: token $TOKEN" \
  "https://api.github.com/repos/zeek-zhao/WorthTrack/actions/runs/$RUN_ID/jobs" \
  | python3 -c "
import sys, json
d = json.load(sys.stdin)
for j in d.get('jobs', []):
    print(f\"== {j['name']} [{j['status']}/{j['conclusion']}]\")
    for s in j.get('steps', []):
        print(f\"   {s['number']:>2}. {s['name']}: {s['conclusion']}\")
"
