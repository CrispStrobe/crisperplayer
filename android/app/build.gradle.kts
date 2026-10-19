plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseStore = System.getenv("CRISPER_ANDROID_KEYSTORE")
val releaseStorePassword = System.getenv("CRISPER_ANDROID_STORE_PASSWORD")
val releaseKeyAlias = System.getenv("CRISPER_ANDROID_KEY_ALIAS")
val releaseKeyPassword = System.getenv("CRISPER_ANDROID_KEY_PASSWORD")
val hasReleaseKey = listOf(releaseStore, releaseStorePassword, releaseKeyAlias, releaseKeyPassword).all { !it.isNullOrBlank() }
require(listOf(releaseStore, releaseStorePassword, releaseKeyAlias, releaseKeyPassword).all { it.isNullOrBlank() } || hasReleaseKey) {
    "Set all four CRISPER_ANDROID signing variables, or none for a local debug-signed build."
}

android {
    namespace = "com.crispstrobe.crisperplayer"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.crispstrobe.crisperplayer"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // Use the minimum supported by this Flutter SDK and its plugins.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = file(releaseStore!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            // Public release CI requires the dedicated persistent release key.
            // Local unsigned configuration retains the debug key for testing.
            signingConfig = signingConfigs.getByName(if (hasReleaseKey) "release" else "debug")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
