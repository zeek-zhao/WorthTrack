#!/usr/bin/env python3
"""上传签名相关 4 个 secrets（文件路径内读，密码不经命令行）。"""
import base64
import json
import urllib.request

from nacl import encoding, public

TOKEN = open("/home/zeek.zhao/.config/worthtrack/gh_token").read().strip()
REPO = "zeek-zhao/WorthTrack"
H = {"Authorization": "Bearer " + TOKEN, "Accept": "application/vnd.github+json"}


def raw_api(p, data=None, method="GET"):
    req = urllib.request.Request(
        f"https://api.github.com/repos/{REPO}{p}",
        data=json.dumps(data).encode() if data is not None else None,
        method=method,
        headers=H,
    )
    body = urllib.request.urlopen(req).read().decode()
    return json.loads(body) if body.strip() else {}


KS_B64 = base64.b64encode(
    open("/home/zeek.zhao/worthtrack-keys/upload-keystore.jks", "rb").read()
).decode()
KS_PASS = open("/home/zeek.zhao/.config/worthtrack/ks_pass").read().strip()
print("b64 len:", len(KS_B64), "| pass len:", len(KS_PASS))

pk_info = raw_api("/actions/secrets/public-key")
pk = public.PublicKey(pk_info["key"].encode(), encoding.Base64Encoder())
sealed = public.SealedBox(pk)

secrets = {
    "KEYSTORE_BASE64": KS_B64,
    "KEYSTORE_PASSWORD": KS_PASS,
    "KEY_ALIAS": "worthtrack",
    "KEY_PASSWORD": KS_PASS,
}
for name, value in secrets.items():
    encrypted = sealed.encrypt(value.encode())
    raw_api(
        f"/actions/secrets/{name}",
        {
            "encrypted_value": base64.b64encode(encrypted).decode(),
            "key_id": pk_info["key_id"],
        },
        "PUT",
    )
    print(f"{name}: uploaded ({len(value)} chars)")
