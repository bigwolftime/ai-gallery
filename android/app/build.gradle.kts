import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Keep the sideload build unchanged. Store channels use their own identity,
// permissions, ordinary Flutter engine and production signing configuration.
val distributionChannel = providers.gradleProperty("distributionChannel").orElse("direct").get()
require(distributionChannel in setOf("direct", "public", "fdroid", "play")) { "Unknown distributionChannel" }
val publicDistribution = distributionChannel != "direct"
val storeDistribution = distributionChannel in setOf("fdroid", "play")
val allowUnsignedStoreRelease = providers.gradleProperty("allowUnsignedStoreRelease").orNull == "true"
val storeKeysFile = rootProject.file("key.properties")
val storeKeys = Properties().apply {
    if (publicDistribution && storeKeysFile.isFile) storeKeysFile.inputStream().use { load(it) }
}

android {
    namespace = "com.aigallery.ai_gallery"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973" // Existing complete NDK; inference uses prebuilt JNI libraries.

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }


    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = if (publicDistribution) "net.zonheng.aigallery" else "com.aigallery.app"
        manifestPlaceholders["aiGalleryDistribution"] = distributionChannel
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        // LiteRT-LM publishes native inference for arm64 and x86_64, not 32-bit ARM.
        ndk {
            abiFilters.clear()
            abiFilters.addAll(listOf("arm64-v8a", "x86_64"))
        }
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    if (publicDistribution) {
        sourceSets.getByName("release").manifest.srcFile(
            if (storeDistribution) "src/store/AndroidManifest.xml" else "src/public/AndroidManifest.xml")
        sourceSets.getByName("release").res.srcDir("src/store/res")
        if (!allowUnsignedStoreRelease) {
            require(storeKeysFile.isFile) { "Store releases require android/key.properties; unsigned builds are for review only." }
            signingConfigs.create("storeRelease") {
                storeFile = rootProject.file(requireNotNull(storeKeys.getProperty("storeFile")))
                storePassword = requireNotNull(storeKeys.getProperty("storePassword"))
                keyAlias = requireNotNull(storeKeys.getProperty("keyAlias"))
                keyPassword = requireNotNull(storeKeys.getProperty("keyPassword"))
            }
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = if (!publicDistribution) signingConfigs.getByName("debug")
                else if (allowUnsignedStoreRelease) null else signingConfigs.getByName("storeRelease")
        }
    }
}

flutter {
    source = "../.."
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}
