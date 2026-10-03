import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing comes from android/key.properties (gitignored). CI writes it from
// the ANDROID_KEYSTORE_* secrets; locally you create it by hand next to the keystore.
// Absent, the release build falls back to debug signing so `flutter run --release`
// still works — the workflow refuses to publish that fallback on production.
val keyPropsFile = rootProject.file("key.properties")
val keyProps = Properties().apply {
    if (keyPropsFile.exists()) {
        keyPropsFile.inputStream().use { load(it) }
    }
}

android {
    namespace = "com.communal.meet"
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
        applicationId = "com.communal.meet"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keyPropsFile.exists()) {
                storeFile = keyProps.getProperty("storeFile")?.let { rootProject.file(it) }
                storePassword = keyProps.getProperty("storePassword")
                keyAlias = keyProps.getProperty("keyAlias")
                keyPassword = keyProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Explicit rather than relying on the variant default: a debuggable
            // release build lets anyone with adb attach to the process and read a
            // member's session token and chat history off the device.
            isDebuggable = false

            signingConfig = if (keyPropsFile.exists()) {
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
