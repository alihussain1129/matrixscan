plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val productionKeystorePath = providers.environmentVariable("EXALTED_ANDROID_KEYSTORE").orNull
val productionStorePassword = providers.environmentVariable("EXALTED_ANDROID_STORE_PASSWORD").orNull
val productionKeyAlias = providers.environmentVariable("EXALTED_ANDROID_KEY_ALIAS").orNull
val productionKeyPassword = providers.environmentVariable("EXALTED_ANDROID_KEY_PASSWORD").orNull
val productionSigningRequired = providers.environmentVariable("EXALTED_REQUIRE_PRODUCTION_SIGNING")
    .orNull?.equals("true", ignoreCase = true) == true
val hasProductionSigning = listOf(
    productionKeystorePath,
    productionStorePassword,
    productionKeyAlias,
    productionKeyPassword,
).all { !it.isNullOrBlank() }

if (productionSigningRequired && !hasProductionSigning) {
    throw GradleException(
        "Production Android signing is required but incomplete. Set " +
            "EXALTED_ANDROID_KEYSTORE, EXALTED_ANDROID_STORE_PASSWORD, " +
            "EXALTED_ANDROID_KEY_ALIAS, and EXALTED_ANDROID_KEY_PASSWORD. " +
            "No signing values are printed."
    )
}

android {
    namespace = "com.exaltedcoding.exalted"
    compileSdk = 37
    ndkVersion = "30.0.16248370"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.exaltedcoding.exalted"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        externalNativeBuild {
            cmake {
                targets += "exalted_ffi"
            }
        }
    }

    // Native C++ core (cpp/) built into libexalted_ffi.so and packaged in the APK.
    externalNativeBuild {
        cmake {
            path = file("../../cpp/CMakeLists.txt")
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasProductionSigning) {
                signingConfigs.create("production") {
                    storeFile = file(productionKeystorePath!!)
                    storePassword = productionStorePassword
                    keyAlias = productionKeyAlias
                    keyPassword = productionKeyPassword
                }
            } else {
                signingConfigs.getByName("debug")
            }
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
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
