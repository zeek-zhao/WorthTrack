#!/usr/bin/env bash
# 本地正式签名构建验证（密码只在脚本内部流转，不经命令行）。
set -euo pipefail
export PATH="$HOME/development/flutter/bin:$PATH"
export JAVA_HOME="$HOME/development/jdk-17"

KS_PASS="$(cat "$HOME/.config/worthtrack/ks_pass")"
echo "password length: ${#KS_PASS}"
export KEYSTORE_PASSWORD="$KS_PASS"
export KEY_ALIAS="worthtrack"
export KEY_PASSWORD="$KS_PASS"

cd /mnt/d/zeek/WorkBuddy/WorthTrack/android
./gradlew --stop >/dev/null 2>&1 || true
./gradlew :app:assembleRelease --no-daemon 2>&1 | tail -5
ls -la ../build/app/outputs/flutter-apk/app-release.apk
