#!/usr/bin/env bash
# WSL 侧 Flutter 环境包装：临时脚本（不进 CI 依赖），供 Windows 侧调用。
# 用法: wsl.exe bash scripts/wt_flutter.sh <command...>
set -euo pipefail
export PATH="$HOME/development/flutter/bin:$PATH"
cd /mnt/d/zeek/WorkBuddy/WorthTrack
exec "$@"
