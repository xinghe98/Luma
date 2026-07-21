import java.io.FileInputStream
import java.util.Properties

val releaseProperties = Properties()
val releasePropertiesFile = rootProject.file("key.properties")
if (releasePropertiesFile.exists()) {
    FileInputStream(releasePropertiesFile).use(releaseProperties::load)
}

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.luma.luma"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.luma.luma"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
			// 只在提供正式密钥时配置 release；绝不回退到 debug 签名。
			// 保持 debug/test 在未配置发布密钥的开发环境中可运行。
			releaseProperties.getProperty("storeFile")?.let { keyFile ->
				signingConfig = signingConfigs.maybeCreate("release").apply {
					storeFile = file(keyFile)
					storePassword = releaseProperties.getProperty("storePassword")
					keyAlias = releaseProperties.getProperty("keyAlias")
					keyPassword = releaseProperties.getProperty("keyPassword")
				}
			}
        }
    }
}

flutter {
    source = "../.."
}
