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
        // T025: JVM unit tests cover the Keystore lifecycle/failure policy;
        // instrumented tests cover the real Android Keystore on a device or
        // emulator. Neither layer substitutes for the other.
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
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

    // T056: bundled Latin ML Kit text recognition. The bundled artifact ships
    // the model in the APK; no Play Services model download and no network
    // call are used by the OCR service.
    implementation("com.google.mlkit:text-recognition:16.0.1")

    // T024: host-JVM contract tests for the platform-channel facade. Test-only;
    // no runtime dependency and no production APK change.
    testImplementation("junit:junit:4.13.2")

    // T025 test layers: policy on the JVM, real Keystore instrumentation.
    androidTestImplementation("androidx.test.ext:junit:1.3.0")
    androidTestImplementation("androidx.test:runner:1.7.0")

    constraints {
        // `integration_test` contributes androidx.test:runner to the debug
        // runtime graph. Pin it to the same version as the instrumentation
        // tests so AGP consistent resolution does not force the transitive
        // 1.3.0 runner onto debugAndroidTestRuntimeClasspath.
        implementation("androidx.test:runner:1.7.0")
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
