#!/usr/bin/env bash
# WorthTrack M1 #1 smoke test: create + build apk debug
set -x
export JAVA_HOME="$HOME/development/jdk-17"
export ANDROID_HOME="$HOME/Android/Sdk"
export PATH="$JAVA_DIR/bin:$JAVA_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$HOME/development/flutter/bin:$PATH"
export PATH="$JAVA_HOME/bin:$PATH"
cd /tmp && rm -rf smoke_worthtrack
flutter create --org com.zeekzhao --project-name worthtrack smoke_worthtrack
cd smoke_worthtrack
flutter build apk --debug
ls -la build/app/outputs/flutter-apk/
echo "SMOKE_DONE"
