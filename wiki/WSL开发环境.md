# WSL 开发环境

> 维护：AI ｜ 最后验证：2026-10-25（flutter doctor 三绿 + 冒烟 APK 构建成功）

WSL 发行版：**Ubuntu-24.04-Zeek**（Ubuntu 24.04.4 LTS, WSL2）

## 已安装组件

| 组件 | 版本 | 位置 |
|---|---|---|
| Flutter SDK | 3.35.4 stable (Dart 3.9.2) | `~/development/flutter` |
| JDK | Temurin 17.0.21+9（用户目录安装，免 sudo） | `~/development/jdk-17` |
| Android SDK | Platform 35/36, build-tools 35.0.0, platform-tools, CMake 3.22.1 | `~/Android/Sdk` |

## 环境变量（已写入 ~/.bashrc）

```bash
export JAVA_HOME="$HOME/development/jdk-17"
export ANDROID_HOME="$HOME/Android/Sdk"
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$HOME/development/flutter/bin:$PATH"
```

## 安装步骤（复现用）

脚本化安装（推荐，仓库内）：`scripts/setup_wsl_env.sh`、`scripts/setup_wsl_env2.sh`、`scripts/smoke_build.sh`

手动步骤：
1. Flutter：下载 `flutter_linux_3.35.4-stable.tar.xz` 解压到 `~/development`，PATH 加入 `~/development/flutter/bin`
2. JDK 17：从 Adoptium 下载 tar.gz 解压到 `~/development/jdk-17`（绕开 sudo apt）
3. Android cmdline-tools：`commandlinetools-linux-11076708_latest.zip` 解压到 `~/Android/Sdk/cmdline-tools/latest`
4. `yes | sdkmanager --licenses`，然后 `sdkmanager "platform-tools" "platforms;android-35" "build-tools;35.0.0"`
5. `flutter config --android-sdk ~/Android/Sdk --no-analytics`

## 验证记录（2026-10-25）

- `flutter doctor`：Flutter ✓ / Android toolchain ✓（licenses 全收）/ Chrome ✓ / Network ✓
- 未装：Linux desktop 工具链（clang/cmake/ninja/pkg-config，需 sudo apt，M4 前补）、Android Studio（CLI 构建不需要）
- 冒烟：`flutter create` + `flutter build apk --debug` 成功（产物 app-debug.apk，首次构建含 Gradle 下载约 5 分钟）

## 已知坑（WSL 特有）

- Windows 宿主调用 `wsl.exe` 传 `/mnt/...` 路径会被 MSYS 转换损坏 → 加 `MSYS_NO_PATHCONV=1`
- WSL 默认 PATH 含 `Program Files (x86)` 括号 → shell 脚本中 PATH 赋值必须加引号
- 用户目录无 sudo 免密 → 需要 root 的包（clang 等）单独请用户执行
