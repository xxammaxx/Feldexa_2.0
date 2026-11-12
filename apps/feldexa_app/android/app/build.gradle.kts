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

// T003: Android-native PDF engine pin. T039/T143 consume this; no current
// application code calls PDFBox yet.
dependencies {
    implementation("com.tom-roush:pdfbox-android:2.0.27.0")

    constraints {
        implementation("org.bouncycastle:bcprov-jdk15to18:1.87")
        implementation("org.bouncycastle:bcpkix-jdk15to18:1.87")
        implementation("org.bouncycastle:bcutil-jdk15to18:1.87")
    }
}

// T003/OD-T003-1: pdfbox-android 2.0.27.0 requests BouncyCastle 1.72, which
// has 12 OSV advisories. Pin the maintained, OSV-clean 1.87 line. Verified
// with the PDFBox public-key encryption/decryption path (JVM regression) and
// an actual Android debug build/dex; see tools/dependency_review.md.
configurations.configureEach {
    resolutionStrategy.eachDependency {
        if (requested.group == "org.bouncycastle" &&
            requested.name in setOf(
                "bcprov-jdk15to18",
                "bcpkix-jdk15to18",
                "bcutil-jdk15to18",
            )
        ) {
            useVersion("1.87")
            because(
                "T003 security pin: pdfbox-android 2.0.27.0 requests BC 1.72; " +
                    "BC 1.87 is the maintained OSV-clean line",
            )
        }
    }
}

flutter {
    source = "../.."
}
