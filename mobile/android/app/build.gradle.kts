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
    id("dev.flutter.flutter-gradle-plugin")
}

val appMetadataProperties = Properties()
val appMetadataPropertiesFile = file("app_metadata.properties")
FileInputStream(appMetadataPropertiesFile).use(appMetadataProperties::load)
val appMetadataApplicationId = requireNotNull(
    appMetadataProperties.getProperty("androidApplicationId"),
) { "app_metadata.properties 缺少 androidApplicationId。" }

android {
    namespace = appMetadataApplicationId
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
        applicationId = appMetadataApplicationId
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // 只打包 arm64-v8a；该过滤只约束本地 jniLibs 与 native build。
        ndk {
            abiFilters += "arm64-v8a"
        }
    }

    packaging {
        jniLibs {
            // 依赖 AAR（libXray.aar、media_kit_libs_video）的原生库不受
            // abiFilters 约束，必须在打包阶段剔除其余 ABI，避免 APK 膨胀三倍。
            excludes += setOf("lib/armeabi-v7a/**", "lib/x86/**", "lib/x86_64/**")
        }
    }

    buildTypes {
        release {
			// 只在提供正式密钥时配置 release；绝不回退到 debug 签名。
			// 保持 debug/test 在未配置发布密钥的开发环境中可运行。
			releaseProperties.getProperty("storeFile")?.let { keyFile ->
				signingConfig = signingConfigs.maybeCreate("release").apply {
					storeFile = rootProject.file(keyFile)
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

dependencies {
    implementation(files("libs/libXray.aar"))
}

val distDir = File(rootProject.projectDir.parentFile, "build/dist")

tasks.matching { it.name == "assembleRelease" }.configureEach {
    doLast {
        copy {
            from(layout.buildDirectory.dir("outputs/apk/release"))
            into(distDir)
            include("*.apk")
        }
    }
}
