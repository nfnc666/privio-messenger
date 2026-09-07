// `java.util.Base64`, imported rather than written out where it is used.
//
// In a project build script the name `java` resolves to the Java plugin's
// extension, not to the package — so `java.util.Base64` reads as "the `util`
// property of the java extension", which does not exist. It compiled nowhere
// and was invisible for a day: the Android build had been failing since the
// dart-define check was added, and no runner was available to say so.
import java.util.Base64

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
        // And through a resource, for the launcher label. AGP 8 turns both of
        // these off by default, and a flavour that sets one without asking for
        // the feature fails at configuration time — which is what the first
        // real Android build of this app found.
        resValues = true
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
            resValue("string", "calculator_name", "Calculator")
            buildConfigField("String", "PRIVIO_EDITION", "\"libre\"")
        }
        // The APK from getprivio.com. The same code and the same dependencies
        // as `libre` — no Firebase, no Play services, woken by UnifiedPush —
        // and a different product all the same: it is called Privio, it is
        // signed by us rather than by F-Droid, and it updates itself from our
        // website instead of from a repository.
        //
        // A flavour of its own rather than "libre with a different name",
        // because the name is in a resource and the edition is in a
        // dart-define, and the two used to be set independently. That produced
        // an APK labelled "Privio Libre" whose Dart side believed it was the
        // website build.
        create("direct") {
            dimension = "distribution"
            resValue("string", "app_name", "Privio")
            resValue("string", "calculator_name", "Calculator")
            buildConfigField("String", "PRIVIO_EDITION", "\"direct\"")
        }
        create("play") {
            dimension = "distribution"
            resValue("string", "app_name", "Privio")
            resValue("string", "calculator_name", "Calculator")
            buildConfigField("String", "PRIVIO_EDITION", "\"play\"")
        }
    }

    // What a notification says when the app is not running to say anything
    // better. Identical in both flavours, and deliberately empty of fact: this
    // text is composed by code that has never seen a plaintext and cannot.
    // Anything more specific would have to come from a decrypted message, and
    // would then be sitting on a lock screen.
    productFlavors.configureEach {
        resValue("string", "notification_channel_messages", "Messages")
        resValue("string", "notification_title", "Privio")
        resValue("string", "notification_body", "You have new activity")
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

/*
 * Refuses a build whose two halves disagree about which edition it is.
 *
 * Gradle picks the flavour and `--dart-define` picks the edition, and nothing
 * connected them. `flutter build apk --flavor libre
 * --dart-define=PRIVIO_EDITION=play` was a perfectly ordinary command that
 * produced an APK named "Privio Libre", containing no Firebase, whose Dart
 * side registered for FCM and hid the licence-key screen. It would have been
 * rejected by F-Droid and would have failed silently for its users.
 *
 * Flutter passes the dart-defines to Gradle as a comma-separated list of
 * base64-encoded `KEY=VALUE` strings in the `dart-defines` property, which is
 * how this reads it without the Dart side having to be running.
 *
 * A missing define is allowed here and refused on the Dart side instead: this
 * has to keep working for `flutter test` and for tooling that never sets one.
 */
fun expectedEditionFor(flavour: String): String = flavour

fun assertEditionMatchesFlavour() {
    val defines = (project.findProperty("dart-defines") as String?)
        ?.split(",")
        ?.mapNotNull {
            runCatching { String(Base64.getDecoder().decode(it.trim())) }.getOrNull()
        }
        ?.mapNotNull { entry ->
            entry.split("=", limit = 2).takeIf { it.size == 2 }?.let { it[0] to it[1] }
        }
        ?.toMap()
        ?: return

    val declared = defines["PRIVIO_EDITION"] ?: return

    // The check belongs to the variant that is *built*, not to every variant
    // that is configured. Gradle configures all of them on every build, so the
    // first version of this — throwing straight out of
    // `applicationVariants.configureEach` — refused a perfectly correct
    // `--flavor libre` build because the `direct` variant also exists and its
    // expected edition is `direct`. All three flavours failed that way the
    // first time CI ever ran this file.
    //
    // Flutter names the task after the flavour (`assembleLibreRelease`) and
    // passes the flavour no other way, so the task name is what says which
    // build this is. Hanging the refusal off that task's own execution also
    // means it fires however the build was started, not only through the
    // Flutter tool.
    //
    // `preBuild` first, and `assemble`/`bundle` only as the backstop: the
    // output task runs *after* everything it depends on, so a refusal there
    // arrives once the Dart and Kotlin have already been compiled — three
    // minutes spent to reject a build that was wrong before it started. CI
    // showed exactly that. `pre<Variant>Build` is the first task in a
    // variant's graph.
    val preBuildTask = Regex("^pre([A-Z]\\w*?)(?:Debug|Profile|Release)Build$")
    val outputTask = Regex("^(?:assemble|bundle)([A-Z]\\w*?)(?:Debug|Profile|Release)$")
    tasks.configureEach {
        val flavour = (preBuildTask.find(name) ?: outputTask.find(name))
            ?.groupValues?.get(1)
            ?.replaceFirstChar { it.lowercaseChar() }
            ?: return@configureEach
        val expected = expectedEditionFor(flavour)
        if (declared == expected) return@configureEach
        doFirst {
            throw org.gradle.api.GradleException(
                "Build refused: --flavor $flavour expects " +
                    "--dart-define=PRIVIO_EDITION=$expected, but it is set to \"$declared\". " +
                    "An APK whose name and whose edition disagree ships as the wrong product."
            )
        }
    }
}

assertEditionMatchesFlavour()

dependencies {
    // The Libre and direct builds' only way of being woken while closed, and
    // the reason they can be: a distributor the user installed, with no Google
    // library in the APK. On Maven Central, so F-Droid can fetch it like any
    // other dependency.
    //
    // Pinned. The API was renamed between 3.x releases — `registerApp` became
    // `register` — so an unpinned bump is a compile error waiting to happen.
    "libreImplementation"("org.unifiedpush.android:connector:3.3.5")
    // The website APK is woken the same way and by the same library. It shares
    // `src/libre` for its Kotlin — see sourceSets below — so it needs the same
    // dependency under its own configuration.
    "directImplementation"("org.unifiedpush.android:connector:3.3.5")

    // Firebase, in the Play flavour and nowhere else. `playImplementation` is
    // what enforces that: there is no build flag that puts these into the
    // Libre APK, and no reviewer has to remember.
    "playImplementation"("com.google.firebase:firebase-messaging:24.1.0")
    "playImplementation"("com.google.android.gms:play-services-base:18.5.0")
}

// Firebase needs `app/google-services.json`, which is configuration for one
// specific Firebase project and is deliberately not in this repository.
//
// Applied only when the file is there, so that a clone without it still builds
// both flavours. Without it the Play build compiles and runs; Firebase simply
// fails to initialise, the bridge answers "no token", and the app tells the
// user it can only be reached while it is open — which is exactly true.
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

// `direct` is `libre` with a different name on it, so it compiles the same
// Kotlin and merges the same manifest rather than keeping a second copy of both
// in step by hand.
android.sourceSets.getByName("direct") {
    kotlin.srcDir("src/libre/kotlin")
    manifest.srcFile("src/libre/AndroidManifest.xml")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
