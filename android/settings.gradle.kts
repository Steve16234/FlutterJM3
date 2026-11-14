pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            val localProperties = file("local.properties")
            require(localProperties.exists()) {
                "local.properties not found at ${localProperties.absolutePath}. " +
                    "Run `flutter pub get` (or `flutter create .`) to generate it."
            }
            localProperties.inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(!flutterSdkPath.isNullOrBlank()) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        // 国内镜像优先，官方仓库兜底
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/gradle-plugin") }
        maven { url = uri("https://maven.aliyun.com/repository/public") }
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    // Flutter 3.50 支持的 AGP 上限是 9.4，KGP 上限见 gradle_utils.dart。
    // 升级前请先确认 flutter doctor 不报 "unsupported AGP version"。
    id("com.android.application") version "9.3.1" apply false
    id("org.jetbrains.kotlin.android") version "2.4.20" apply false
}

include(":app")
