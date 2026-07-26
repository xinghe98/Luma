pluginManagement {
    val useChinaMavenMirrors =
        providers.gradleProperty("luma.useChinaMirrors").orNull?.toBooleanStrictOrNull()
            ?: System.getenv("LUMA_USE_CHINA_MIRRORS")?.toBooleanStrictOrNull()
            ?: false
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        if (useChinaMavenMirrors) {
            maven(url = "https://maven.aliyun.com/repository/google")
            maven(url = "https://maven.aliyun.com/repository/central")
            maven(url = "https://maven.aliyun.com/repository/gradle-plugin")
            maven(url = "https://maven.aliyun.com/repository/public")
        }
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}

val useChinaMavenMirrors =
    providers.gradleProperty("luma.useChinaMirrors").orNull?.toBooleanStrictOrNull()
        ?: System.getenv("LUMA_USE_CHINA_MIRRORS")?.toBooleanStrictOrNull()
        ?: false

// 镜像仅在显式开启时注入 Flutter 插件项目，默认始终使用官方仓库。
if (useChinaMavenMirrors) {
    gradle.beforeProject {
        buildscript {
            repositories {
                maven(url = "https://maven.aliyun.com/repository/google")
                maven(url = "https://maven.aliyun.com/repository/central")
                maven(url = "https://maven.aliyun.com/repository/gradle-plugin")
                maven(url = "https://maven.aliyun.com/repository/public")
                google()
                mavenCentral()
                gradlePluginPortal()
            }
        }
        repositories {
            maven(url = "https://maven.aliyun.com/repository/google")
            maven(url = "https://maven.aliyun.com/repository/central")
            maven(url = "https://maven.aliyun.com/repository/public")
            google()
            mavenCentral()
        }
    }
}

include(":app")
