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

// TV ABI 选择：缺省保持 arm64-v8a（手机包行为不变）；
// lumaTvAbis=arm 打 32+64 位双 ARM 电视包；emulator 仅 x86_64 供隔离模拟器验证。
val allNativeAbis = setOf("armeabi-v7a", "arm64-v8a", "x86", "x86_64")
val lumaTvAbisProperty = providers.gradleProperty("lumaTvAbis")
val nativeAbiFilters: Set<String> = when (val lumaTvAbis = lumaTvAbisProperty.orNull) {
    null -> setOf("arm64-v8a")
    "arm" -> setOf("armeabi-v7a", "arm64-v8a")
    "emulator" -> setOf("x86_64")
    else -> throw GradleException("lumaTvAbis 仅支持 arm 或 emulator")
}

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
        // ABI 过滤只约束本地 jniLibs 与 native build，由 lumaTvAbis 统一派生。
        ndk {
            abiFilters += nativeAbiFilters
        }
    }

    packaging {
        jniLibs {
            // 依赖 AAR（libXray.aar、media_kit_libs_video）的原生库不受
            // abiFilters 约束，必须在打包阶段剔除未选 ABI，避免 APK 膨胀三倍。
            // excludes 与 abiFilters 出自同一选择，保证两者一致。
            excludes += (allNativeAbis - nativeAbiFilters).map { "lib/$it/**" }.toSet()
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
            // TV 双 ARM 包独立命名，避免覆盖普通手机产物；普通路径命名不变。
            if (lumaTvAbisProperty.orNull == "arm") {
                rename { fileName ->
                    fileName.replace("app-release", "luma-tv-arm-${flutter.versionName}-release")
                }
            }
        }
    }
}
