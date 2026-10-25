plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 正式签名：keystore 由 CI 的 Restore keystore 步骤还原到 android/app/upload-keystore.jks，
// 密码通过环境变量提供（GitHub Secrets）。keystore 文件与密码都不入库。
val releaseKeystore = file("upload-keystore.jks")

android {
    namespace = "com.zeekzhao.worthtrack"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.zeekzhao.worthtrack"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseKeystore.exists()) {
            create("release") {
                storeFile = releaseKeystore
                storePassword = System.getenv("KEYSTORE_PASSWORD")
                    ?: error("环境变量 KEYSTORE_PASSWORD 缺失：本地发正式包请先设置签名环境变量")
                keyAlias = System.getenv("KEY_ALIAS") ?: "worthtrack"
                keyPassword = System.getenv("KEY_PASSWORD")
                    ?: error("环境变量 KEY_PASSWORD 缺失：本地发正式包请先设置签名环境变量")
            }
        }
    }

    buildTypes {
        release {
            // 有正式 keystore 用正式签名，否则退回 debug 签名（仅本地调试用）。
            signingConfig = if (releaseKeystore.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}
