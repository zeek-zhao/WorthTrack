#!/usr/bin/env python3
"""上传 GitHub Actions 仓库 secrets（libsodium sealed box 加密）。

用法: python3 set_secrets.py NAME=VALUE [NAME=VALUE ...]
"""
import base64
import json
import sys
import urllib.request

from nacl import encoding, public

TOKEN = open("/home/zeek.zhao/.config/worthtrack/gh_token").read().strip()
REPO = "zeek-zhao/WorthTrack"
H = {"Authorization": "Bearer " + TOKEN, "Accept": "application/vnd.github+json"}


def api(p, data=None, method="GET"):
    req = urllib.request.Request(
        f"https://api.github.com/repos/{REPO}{p}",
        data=json.dumps(data).encode() if data is not None else None,
        method=method,
        headers=H,
    )
    return json.loads(urllib.request.urlopen(req).read().decode())


def main():
    pk_info = api("/actions/secrets/public-key")
    pk = public.PublicKey(pk_info["key"].encode(), encoding.Base64Encoder())
    sealed = public.SealedBox(pk)

    for item in sys.argv[1:]:
        name, _, value = item.partition("=")
        encrypted = sealed.encrypt(value.encode())
        api(
            f"/actions/secrets/{name}",
            {
                "encrypted_value": base64.b64encode(encrypted).decode(),
                "key_id": pk_info["key_id"],
            },
            "PUT",
        )
        print(f"{name}: uploaded")


if __name__ == "__main__":
    main()
