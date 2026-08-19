import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Firebase Cloud Messaging config, same shape as the release keystore below:
// machine-local, git-ignored, and absent by default so a fresh checkout builds.
// The google-services plugin aborts the build if applied without the file, so
// it is applied conditionally rather than declared in the `plugins` block —
// which cannot be conditional.
//
// When the file is missing, the app builds and runs with push disabled: see
// PushService, which reports Firebase as unconfigured rather than crashing.
val googleServicesFile = file("google-services.json")
if (googleServicesFile.exists()) {
    apply(plugin = "com.google.gms.google-services")
} else {
    logger.lifecycle(
        "google-services.json not found — building without push. See README's Push section.",
    )
}

// Release signing is optional and machine-local: `key.properties` is
// git-ignored (see .gitignore) and absent by default, so a fresh checkout
// still builds. When present, it points at a keystore for release signing;
// see README.md for how to generate one. When absent, the release build
// type falls back to debug signing further down.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val hasKeystoreProperties = keystorePropertiesFile.exists()
if (hasKeystoreProperties) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

android {
    namespace = "com.sagnikdas.dosely"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.sagnikdas.dosely"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasKeystoreProperties) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Uses the real release keystore when app/android/key.properties
            // exists (see README.md to generate one); otherwise falls back to
            // debug signing so `flutter build apk`/`flutter run --release`
            // keep working out of the box on a fresh checkout.
            signingConfig =
                if (hasKeystoreProperties) {
                    signingConfigs.getByName("release")
                } else {
                    signingConfigs.getByName("debug")
                }
            // Minify only in release so the Kotlin/Java surface is not shipped
            // readable. Debug and profile stay unminified so iteration and
            // attached-device debugging stay fast.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
