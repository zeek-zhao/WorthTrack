#!/usr/bin/env python3
"""Create WorthTrack GitHub Projects v2 board, add all issues, set status."""
import json
import os
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
    with urllib.request.urlopen(req) as r:
        return json.loads(r.read().decode())


def gql(query, variables=None):
    req = urllib.request.Request(
        "https://api.github.com/graphql",
        data=json.dumps({"query": query, "variables": variables or {}}).encode(),
        method="POST",
        headers={"Authorization": f"Bearer {TOKEN}"},
    )
    with urllib.request.urlopen(req) as r:
        out = json.loads(r.read().decode())
    if "errors" in out:
        raise RuntimeError(json.dumps(out["errors"], ensure_ascii=False)[:500])
    return out["data"]


# 1. owner + project
user = rest("/user")
owner_id = user["node_id"]
proj = gql(
    'mutation($o:ID!){createProjectV2(input:{ownerId:$o,title:"WorthTrack 开发看板"}){projectV2{id number url}}}',
    {"o": owner_id},
)["createProjectV2"]["projectV2"]
print(f"project #{proj['number']} {proj['url']}")

pid = proj["id"]

# 2. ensure Status single-select field with Todo/In Progress/Done
fields = gql(
    'query($id:ID!){node(id:$id){... on ProjectV2{fields(first:20){nodes{... on ProjectV2Field{id name}... on ProjectV2SingleSelectField{id name options{id name}}}}}}}',
    {"id": pid},
)["node"]["fields"]["nodes"]
status = next((f for f in fields if f["name"] == "Status"), None)
if status is None:
    status = gql(
        'mutation($p:ID!){createProjectV2Field(input:{projectId:$p,dataType:SINGLE_SELECT,name:"Status",'
        'singleSelectOptions:[{name:"Todo"},{name:"In Progress"},{name:"Done"}]})'
        "{projectV2Field{... on ProjectV2SingleSelectField{id options{id name}}}}}",
        {"p": pid},
    )["createProjectV2Field"]["projectV2Field"]
opts = {o["name"]: o["id"] for o in status["options"]}
print("status options:", list(opts))

# 3. add all issues
issues = rest(f"/repos/{REPO}/issues?state=open&per_page=100")
for it in issues:
    item = gql(
        'mutation($p:ID!,$c:ID!){addProjectV2ItemById(input:{projectId:$p,contentId:$c}){item{id}}}',
        {"p": pid, "c": it["node_id"]},
    )["addProjectV2ItemById"]["item"]
    target = "In Progress" if it["number"] == 1 else "Todo"
    gql(
        'mutation($p:ID!,$i:ID!,$f:ID!,$o:String!){updateProjectV2ItemFieldValue(input:{projectId:$p,itemId:$i,'
        'fieldId:$f,value:{singleSelectOptionId:$o}}){projectV2Item{id}}}',
        {"p": pid, "i": item["id"], "f": status["id"], "o": opts[target]},
    )
    print(f"added #{it['number']} -> {target}")

print("BOARD DONE:", proj["url"])
