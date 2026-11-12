plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Kotlin: android.builtInKotlin=false keeps Flutter's supported KGP path.
// FlutterPluginUtils.detectApplyingKotlinGradlePlugin applies
// org.jetbrains.kotlin.android to this module because it does not declare KGP;
// MainActivity.kt is therefore compiled (verified in the APK DEX).
android {
    namespace = "de.feldexa.app"
    // T002: Android 8.0 (API 26) minimum; Android 16 (API 36) compile/target.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "de.feldexa.app"
        minSdk = 26
        targetSdk = 36
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Intentionally unsigned: T002 configures no release signing identity
            // and no credentials are committed. Production signing is a later,
            // owner-supplied integration step; no release-signing claim is made.
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
