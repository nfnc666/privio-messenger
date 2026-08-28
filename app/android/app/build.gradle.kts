plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "app.privio.privio"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        // The flavours below publish their identity through BuildConfig, so
        // anything on the Android side can tell which build it is in without
        // guessing from the package name.
        buildConfig = true
    }

    defaultConfig {
        // One application id for every channel. F-Droid, the direct APK and
        // Play all install "app.privio.privio"; they differ in who signed the
        // binary, not in what it claims to be.
        applicationId = "app.privio.privio"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Two ways to get the same app, split at build time rather than at runtime.
    //
    // `libre` is what F-Droid builds and what the direct APK is cut from: free
    // software only, no proprietary SDK, activated with a license key bought on
    // the website. `play` is the Google Play build, paid for in the store, and
    // the only variant that may ever depend on Google Play services.
    //
    // The split exists so that "the F-Droid build contains no proprietary code"
    // is enforced by the build system instead of by remembering. A dependency
    // added for push, billing or maps belongs in `playImplementation`, never in
    // `implementation`.
    flavorDimensions += "distribution"

    productFlavors {
        create("libre") {
            dimension = "distribution"
            resValue("string", "app_name", "Privio Libre")
            buildConfigField("String", "PRIVIO_EDITION", "\"libre\"")
        }
        create("play") {
            dimension = "distribution"
            resValue("string", "app_name", "Privio")
            buildConfigField("String", "PRIVIO_EDITION", "\"play\"")
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            //
            // F-Droid signs its own build regardless of what is set here, which
            // is why a Libre APK from F-Droid and one built locally have
            // different signatures and cannot update each other.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    // The dependency-metadata blob Gradle normally embeds is signed by Google
    // and is not reproducible from source, so a build with it in cannot be
    // verified against F-Droid's. Off for every variant: nothing needs it.
    dependenciesInfo {
        includeInApk = false
        includeInBundle = false
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
