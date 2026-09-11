plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.piyushbaniya.vorafind"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.piyushbaniya.vorafind"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // JVM unit tests for the pure capability/permission state logic.
    // Test-only dependency; does not affect the APK.
    testImplementation("junit:junit:4.13.2")

    // Local, bundled ML Kit text recognition (on-device OCR; bundled model
    // means no Play Services download and full offline use). Note: the bundled
    // model adds ~20MB to the APK. Trade-off accepted for off-device OCR.
    implementation("com.google.mlkit:text-recognition:16.0.1")

    // EXIF orientation for correct OCR of camera photos (auto-rotation needs
    // API 28+ ImageDecoder; using this keeps a single decode path on minSdk 24).
    implementation("androidx.exifinterface:exifinterface:1.4.1")
}

flutter {
    source = "../.."
}
