plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.valasek.auctionbaby.android"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.valasek.auctionbaby.android"
        minSdk = 24
        targetSdk = 35
        versionCode = 1
        versionName = "1.0.0"

        manifestPlaceholders["hostName"] = "mvalasek77.github.io"
        manifestPlaceholders["defaultUrl"] = "https://mvalasek77.github.io/auctionbaby/app/"
        manifestPlaceholders["launcherName"] = "Auction Baby"
        manifestPlaceholders["assetStatements"] = """[{"relation": ["delegate_permission/common.handle_all_urls"], "target": {"namespace": "web", "site": "https://mvalasek77.github.io"}}]"""
    }

    signingConfigs {
        create("release") {
            // Set these via environment variables or local.properties:
            //   KEYSTORE_FILE, KEYSTORE_PASSWORD, KEY_ALIAS, KEY_PASSWORD
            val ksFile = findProperty("KEYSTORE_FILE") as String?
                ?: System.getenv("KEYSTORE_FILE")
            val ksPwd = findProperty("KEYSTORE_PASSWORD") as String?
                ?: System.getenv("KEYSTORE_PASSWORD")
            val kAlias = findProperty("KEY_ALIAS") as String?
                ?: System.getenv("KEY_ALIAS")
            val kPwd = findProperty("KEY_PASSWORD") as String?
                ?: System.getenv("KEY_PASSWORD")
            if (ksFile != null && ksPwd != null && kAlias != null && kPwd != null) {
                storeFile = file(ksFile)
                storePassword = ksPwd
                keyAlias = kAlias
                keyPassword = kPwd
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            signingConfig = signingConfigs.findByName("release")
        }
        debug {
            applicationIdSuffix = ".debug"
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }
}

dependencies {
    implementation("androidx.browser:browser:1.8.0")
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("com.google.androidbrowserhelper:androidbrowserhelper:2.5.0")
}
