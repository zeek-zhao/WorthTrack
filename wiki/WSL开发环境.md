# WSL 开发环境

> 维护：AI ｜ 最后验证：2026-10-28（flutter doctor 三绿 + 冒烟 APK 构建成功 + 集成测试在 CI 全绿）

WSL 发行版：**Ubuntu-24.04-Zeek**（Ubuntu 24.04.4 LTS, WSL2）

## 已安装组件

| 组件 | 版本 | 位置 |
|---|---|---|
| Flutter SDK | 3.35.4 stable (Dart 3.9.2) | `~/development/flutter` |
| JDK | Temurin 17.0.21+9（用户目录安装，免 sudo） | `~/development/jdk-17` |
| Android SDK | Platform 35/36, build-tools 35.0.0, platform-tools, CMake 3.22.1 | `~/Android/Sdk` |
| libsqlite3（测试用） | 系统包解出到用户目录 | `~/.local/lib/libsqlite3.so`（见 `scripts/setup_sqlite3_local.sh`） |

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

## 验证记录

- **2026-10-25**：`flutter doctor` Flutter ✓ / Android toolchain ✓（licenses 全收）/ Chrome ✓ / Network ✓；
  `flutter build apk --debug` 成功（产物 app-debug.apk，首次构建含 Gradle 下载约 5 分钟）
- **2026-10-28**：单测 299 个本地全绿；集成测试 13 条在 **CI（ubuntu-latest + xvfb）** 全绿。
  本地未装 Linux 桌面工具链，因此**集成测试一律由 CI 跑**（见下节）。

## 集成测试怎么跑（重要）

`integration_test/money_paths_test.dart` 会编译出 Linux 桌面宿主程序，需要：

```bash
sudo apt-get update
sudo apt-get install -y clang cmake ninja-build pkg-config libgtk-3-dev xvfb
xvfb-run -a bash scripts/wt_flutter.sh flutter test integration_test
```

- 没装上面这些包时，本地跑集成测试会卡在 CMake/GTK 阶段直接失败——**不是代码问题**
- 这些包需要 sudo，本机按「用户目录免 sudo」原则没有装，所以**日常靠 CI 验证集成测试**
- 铁律：**集成测试只允许一个文件**（第二个文件在 CI 里应用启动稳定失败，见 troubleshooting 1.5）

## 依赖说明（v0.4.0 新增）

| 依赖 | 用途 | 备注 |
|---|---|---|
| `file_picker` ^11 | 备份导出/恢复、CSV 导出的「另存为」 | Android 走 SAF（`saveFile(bytes:)` 必须传内容）；桌面只返回路径，内容由应用自己写 |
| `crypto` ^3 | PIN 的 PBKDF2-HMAC-SHA256 | 只在设置/解锁时用 |
| `fast_gbk` ^1 | 腾讯行情 GBK 解码 | 必须解码后再按 `~` 切分，否则中文名里的 0x7E 会让列错位 |

## 已知坑（WSL 特有）

- Windows 宿主调用 `wsl.exe` 传 `/mnt/...` 路径会被 MSYS 转换损坏 → 加 `MSYS_NO_PATHCONV=1`
- WSL 默认 PATH 含 `Program Files (x86)` 括号 → shell 脚本中 PATH 赋值必须加引号
- 用户目录无 sudo 免密 → 需要 root 的包（clang 等）单独请用户执行
- 多层 shell 嵌套会让 `$(cat file)` 展开成空（表现为 token「假失效」401）→ 含密码/token 的操作一律写成 `scripts/*.sh` 执行
