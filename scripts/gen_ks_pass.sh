#!/usr/bin/env bash
# 生成随机 keystore 密码写入 ~/.config/worthtrack/ks_pass（600 权限）。
umask 077
mkdir -p ~/.config/worthtrack
P="WTk3y$(head -c 9 /dev/urandom | base64 | tr -d '/+=')"
printf '%s' "$P" > ~/.config/worthtrack/ks_pass
echo "password length: ${#P}"
wc -c < ~/.config/worthtrack/ks_pass
