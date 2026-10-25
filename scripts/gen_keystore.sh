#!/usr/bin/env bash
# 生成 WorthTrack 上架签名 keystore（仅本地保留，绝不入库）。
# 密码通过环境变量 WT_KS_PASS 传入，不在命令行/文件中留存。
set -euo pipefail

KS="$HOME/worthtrack-keys/upload-keystore.jks"
mkdir -p "$(dirname "$KS")"

if [ -f "$KS" ]; then
  echo "keystore 已存在: $KS"
  exit 0
fi

: "${WT_KS_PASS:?需要设置 WT_KS_PASS}"

"$HOME/development/jdk-17/bin/keytool" -genkeypair -v \
  -keystore "$KS" -alias worthtrack -keyalg RSA -keysize 2048 -validity 10000 \
  -storetype JKS \
  -storepass "$WT_KS_PASS" -keypass "$WT_KS_PASS" \
  -dname "CN=WorthTrack, OU=Personal, O=zeekzhao, L=Shanghai, ST=Shanghai, C=CN"

echo "OK: $KS"
