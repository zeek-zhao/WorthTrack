#!/usr/bin/env python3
"""Fill GitHub milestones + project board, close #1, create PR. Token from file."""
import json
import os
import sys
import urllib.request

TOKEN = open(os.path.expanduser("~/.config/worthtrack/gh_token")).read().strip()
REPO = "zeek-zhao/WorthTrack"


def rest(path, data=None, method="GET"):
    req = urllib.request.Request(
        f"https://api.github.com{path}",
        data=json.dumps(data).encode() if data else None,
        method=method,
        headers={"Authorization": f"Bearer {TOKEN}", "Accept": "application/vnd.github+json"},
    )
    try:
        with urllib.request.urlopen(req) as r:
            return json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        body = e.read().decode()[:300]
        print(f"ERR {method} {path}: {e.code} {body}")
        return None


def gql(query, variables=None):
    req = urllib.request.Request(
        "https://api.github.com/graphql",
        data=json.dumps({"query": query, "variables": variables or {}}).encode(),
        method="POST",
        headers={"Authorization": f"Bearer {TOKEN}"},
    )
    try:
        with urllib.request.urlopen(req) as r:
            out = json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        print(f"GQL HTTP {e.code}: {e.read().decode()[:300]}")
        return None
    if "errors" in out:
        print("GQL ERR:", json.dumps(out["errors"], ensure_ascii=False)[:300])
        return None
    return out["data"]


me = rest("/user")
if me is None:
    print("FATAL: token invalid")
    sys.exit(1)
print(f"token OK: {me['login']}")

# 1. close issue #1
r = rest("/repos/zeek-zhao/WorthTrack/issues/1", {"state": "closed", "state_reason": "completed"}, "PATCH")
print("issue #1:", (r or {}).get("state"))

# 2. create PR if not exists
prs = rest("/repos/zeek-zhao/WorthTrack/pulls?head=zeek-zhao:feat/scaffold&base=main&state=open")
if prs:
    print("PR exists:", prs[0]["number"])
else:
    pr = rest("/repos/zeek-zhao/WorthTrack/pulls", {
        "title": "feat: Flutter 项目脚手架（Riverpod/Drift 依赖 + 最小应用骨架）",
        "head": "feat/scaffold", "base": "main",
        "body": "Closes #2\n\n- flutter create（android/linux/windows 三端，org com.zeekzhao）\n- 依赖：flutter_riverpod / drift / intl / fl_chart + dev(drift_dev, build_runner)\n- lib 最小骨架：ProviderScope 入口 + Material 3 中文主题占位首页\n- 默认计数器测试替换为应用冒烟测试\n\n## 自查\n- [x] dart format --set-exit-if-changed 通过\n- [x] flutter analyze 无 warning\n- [x] flutter test 通过",
    }, "POST")
    print("PR created:", (pr or {}).get("number", (pr or {}).get("message")))

# 3. milestones: create M1-M4, assign issues by label
titles = {"M1": "M1 记账核心", "M2": "M2 报表与预算", "M3": "M3 投资跟踪", "M4": "M4 备份与打磨"}
existing = {m["title"]: m["number"] for m in (rest("/repos/zeek-zhao/WorthTrack/milestones?state=all") or [])}
for tag, title in titles.items():
    if title not in existing:
        m = rest("/repos/zeek-zhao/WorthTrack/milestones", {"title": title}, "POST")
        existing[title] = m["number"]
    print(f"milestone {title} -> #{existing[title]}")

issues = rest("/repos/zeek-zhao/WorthTrack/issues?state=open&per_page=100")
for it in issues:
    labels = [l["name"] for l in it["labels"] if l["name"] in titles]
    if labels:
        r = rest(f"/repos/zeek-zhao/WorthTrack/issues/{it['number']}",
                 {"milestone": existing[titles[labels[0]]]}, "PATCH")
        print(f"#{it['number']} -> {titles[labels[0]]}")

# 4. project board (user's manually created "WorthTrack")
projects = gql(
    'query{user(login:"zeek-zhao"){projectsV2(first:20){nodes{id number title}}}}'
)
if projects:
    nodes = projects["user"]["projectsV2"]["nodes"]
    print("projects:", [(p["number"], p["title"]) for p in nodes])
    proj = next((p for p in nodes if "WorthTrack" in p["title"]), nodes[0] if nodes else None)
    if proj:
        pid = proj["id"]
        fields = gql(
            'query($id:ID!){node(id:$id){... on ProjectV2{fields(first:20){nodes{... on ProjectV2Field{id name}'
            '... on ProjectV2SingleSelectField{id name options{id name}}}}}}}', {"id": pid},
        )["node"]["fields"]["nodes"]
        status = next((f for f in fields if f["name"] == "Status"), None)
        opts = {o["name"]: o["id"] for o in status["options"]} if status else {}
        print("status options:", list(opts))
        items = gql('query($id:ID!){node(id:$id){... on ProjectV2{items(first:100){nodes{content{... on Issue{number}}}}}}}',
                    {"id": pid})["node"]["items"]["nodes"]
        existing_nums = {i["content"]["number"] for i in items if i.get("content") and "number" in i["content"]}
        for it in issues:
            if it["number"] in existing_nums:
                continue
            item = gql(
                'mutation($p:ID!,$c:ID!){addProjectV2ItemById(input:{projectId:$p,contentId:$c}){item{id}}}',
                {"p": pid, "c": it["node_id"]},
            )
            if item is None:
                continue
            item_id = item["addProjectV2ItemById"]["item"]["id"]
            target = "In Progress" if it["number"] == 2 else "Todo"
            if status:
                gql(
                    'mutation($p:ID!,$i:ID!,$f:ID!,$o:String!){updateProjectV2ItemFieldValue(input:{projectId:$p,itemId:$i,'
                    'fieldId:$f,value:{singleSelectOptionId:$o}}){projectV2Item{id}}}',
                    {"p": pid, "i": item_id, "f": status["id"], "o": opts.get(target)},
                )
            print(f"board add #{it['number']} -> {target}")
print("ALL_DONE")
