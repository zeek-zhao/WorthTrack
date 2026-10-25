#!/usr/bin/env bash
# WorthTrack M1 #1 (part 2): JDK 17 user-local + Android SDK packages
set -x

# 1. JDK 17 (Temurin, user-local, no sudo)
JAVA_DIR="$HOME/development/jdk-17"
if [ ! -x "$JAVA_DIR/bin/java" ]; then
  cd /tmp || exit 1
  curl -sL -o jdk17.tar.gz "https://api.adoptium.net/v3/binary/latest/17/ga/linux/x64/jdk/hotspot/normal/eclipse"
  rm -rf /tmp/jdk17 && mkdir -p /tmp/jdk17
  tar xf jdk17.tar.gz -C /tmp/jdk17
  rm -rf "$JAVA_DIR" && mv /tmp/jdk17/jdk-* "$JAVA_DIR"
fi
export JAVA_HOME="$JAVA_DIR"
"$JAVA_DIR/bin/java" -version

# 2. persist env in bashrc
grep -q "JAVA_HOME" ~/.bashrc || cat >> ~/.bashrc <<'EOF'
export JAVA_HOME="$HOME/development/jdk-17"
export ANDROID_HOME="$HOME/Android/Sdk"
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$HOME/development/flutter/bin:$PATH"
EOF
grep -q "ANDROID_HOME" ~/.bashrc || sed -i 's|^export JAVA_HOME=.*|&\nexport ANDROID_HOME="$HOME/Android/Sdk"\nexport PATH="$JAVA_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$HOME/development/flutter/bin:$PATH"|' ~/.bashrc

export ANDROID_HOME="$HOME/Android/Sdk"
export PATH="$JAVA_DIR/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$HOME/development/flutter/bin:$PATH"

# 3. Android SDK licenses + packages
yes | sdkmanager --licenses >/dev/null 2>&1 || true
sdkmanager "platform-tools" "platforms;android-35" "build-tools;35.0.0"

# 4. flutter doctor
flutter config --android-sdk "$ANDROID_HOME" --no-analytics
flutter doctor -v
echo "SETUP2_DONE"
