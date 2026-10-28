#!/usr/bin/env bash
# 把 docs/release-notes/<tag>.md 的内容写进该 tag 的 GitHub Release 正文
# 用法：bash scripts/set_release_body.sh v0.4.0
set -euo pipefail
TAG=${1:?usage: set_release_body.sh <tag>}
BODY="docs/release-notes/$TAG.md"
TOKEN=$(cat "$HOME/.config/worthtrack/gh_token")
REPO=zeek-zhao/WorthTrack

python3 - "$TAG" "$BODY" "$TOKEN" "$REPO" <<'PY'
import json, sys, urllib.request

tag, body_path, token, repo = sys.argv[1:5]
body = open(body_path, encoding="utf-8").read()
base = f"https://api.github.com/repos/{repo}"
headers = {"Authorization": "Bearer " + token, "Accept": "application/vnd.github+json"}

req = urllib.request.Request(f"{base}/releases/tags/{tag}", headers=headers)
release = json.loads(urllib.request.urlopen(req).read().decode())

data = json.dumps({"body": body}).encode()
req = urllib.request.Request(
    f"{base}/releases/{release['id']}", data=data, headers=headers, method="PATCH"
)
updated = json.loads(urllib.request.urlopen(req).read().decode())
print("updated:", updated["html_url"], "body_chars=", len(updated.get("body") or ""))
PY
