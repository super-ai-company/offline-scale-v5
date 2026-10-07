plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.vdamov3.cashier_trae"
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
        applicationId = "com.vdamov3.cashier_trae"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    flavorDimensions += "distribution"
    productFlavors {
        create("website") {
            dimension = "distribution"
            signingConfig = signingConfigs.getByName("debug")
        }
        create("play") {
            dimension = "distribution"
            applicationId = "com.superaicompany.offlinescale"
        }
    }

    buildTypes {
        debug {
            applicationIdSuffix = ".visiondev"
            versionNameSuffix = "-vision-dev"
            ndk.abiFilters.add("arm64-v8a")
        }
        release {
            // Website retains its legacy signer. Play candidates remain unsigned
            // until a production upload key is configured; never use a debug key.
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    // 让 Gradle 能找到 libs/ 下的 AAR
    sourceSets {
        getByName("main") {
            jniLibs.srcDirs("libs")
        }
    }
}

dependencies {
    // 称重串口库（来自 WeightDemo）
    implementation(fileTree(mapOf("dir" to "libs", "include" to listOf("*.aar", "*.jar"))))
    implementation("com.sunmi:printerlibrary:1.0.24")
    implementation("com.google.mediapipe:tasks-vision:0.10.35")
}

flutter {
    source = "../.."
}

// Keep test APK transport small without changing release packaging/signatures.
androidComponents {
    onVariants(selector().withBuildType("debug")) { variant ->
        variant.packaging.jniLibs.useLegacyPackaging.set(true)
    }
}
