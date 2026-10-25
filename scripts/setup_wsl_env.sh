#!/usr/bin/env bash
# WorthTrack M1 #1: WSL Flutter/Android environment setup
set -x

# 1. flutter PATH in bashrc
grep -q "development/flutter" ~/.bashrc || echo 'export PATH="$HOME/development/flutter/bin:$PATH"' >> ~/.bashrc

# 2. JDK 17 (needs passwordless sudo; skip if java already present)
if ! command -v java >/dev/null 2>&1; then
  sudo -n apt-get update -y && sudo -n apt-get install -y openjdk-17-jdk-headless unzip
else
  echo "java already present: $(java -version 2>&1 | head -1)"
fi

# 3. Android SDK cmdline-tools
SDK="$HOME/Android/Sdk"
if [ ! -d "$SDK/cmdline-tools/latest" ]; then
  mkdir -p "$SDK/cmdline-tools"
  cd /tmp || exit 1
  curl -sL -o cmdtools.zip https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip
  rm -rf /tmp/ct && unzip -q cmdtools.zip -d /tmp/ct
  mv /tmp/ct/cmdline-tools "$SDK/cmdline-tools/latest"
fi
export ANDROID_HOME="$SDK"
export PATH="$HOME/development/flutter/bin:$SDK/cmdline-tools/latest/bin:$SDK/platform-tools:$PATH"

# 4. licenses + packages
yes | sdkmanager --licenses >/dev/null 2>&1 || true
sdkmanager "platform-tools" "platforms;android-35" "build-tools;35.0.0"

# 5. flutter doctor
flutter config --android-sdk "$SDK" --no-analytics
flutter doctor -v
echo "SETUP_SCRIPT_DONE"
