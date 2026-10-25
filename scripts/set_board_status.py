#!/usr/bin/env python3
"""Set a project board item's Status. Usage: set_board_status.py <issue_number> <Status>"""
import json
import os
import sys
import urllib.request

TOKEN = open(os.path.expanduser("~/.config/worthtrack/gh_token")).read().strip()
issue_no = int(sys.argv[1])
target = sys.argv[2] if len(sys.argv) > 2 else "Done"


def gql(q, v=None):
    req = urllib.request.Request(
        "https://api.github.com/graphql",
        data=json.dumps({"query": q, "variables": v or {}}).encode(),
        method="POST", headers={"Authorization": f"Bearer {TOKEN}"})
    out = json.loads(urllib.request.urlopen(req).read().decode())
    if "errors" in out:
        raise RuntimeError(out["errors"])
    return out["data"]


proj = next(p for p in gql('query{user(login:"zeek-zhao"){projectsV2(first:20){nodes{id number title}}}}')
            ["user"]["projectsV2"]["nodes"] if "WorthTrack" in p["title"])
pid = proj["id"]
fields = gql('query($id:ID!){node(id:$id){... on ProjectV2{fields(first:20){nodes{... on ProjectV2Field{id name}'
             '... on ProjectV2SingleSelectField{id name options{id name}}}}}}}', {"id": pid})["node"]["fields"]["nodes"]
status = next(f for f in fields if f["name"] == "Status")
opt = next(o["id"] for o in status["options"] if o["name"] == target)
items = gql('query($id:ID!){node(id:$id){... on ProjectV2{items(first:100){nodes{id content{... on Issue{number}}}}}}}',
            {"id": pid})["node"]["items"]["nodes"]
item = next(i for i in items if i.get("content") and i["content"].get("number") == issue_no)
gql('mutation($p:ID!,$i:ID!,$f:ID!,$o:String!){updateProjectV2ItemFieldValue(input:{projectId:$p,itemId:$i,'
    'fieldId:$f,value:{singleSelectOptionId:$o}}){projectV2Item{id}}}',
    {"p": pid, "i": item["id"], "f": status["id"], "o": opt})
print(f"#{issue_no} -> {target}")
