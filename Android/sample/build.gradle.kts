plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
}

android {
    namespace = "com.olaf.sample"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.olaf.sample"
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
    }
}

dependencies {
    // Wired exactly the way a host app should wire it — and this doubles as the API-compatibility
    // check: the same sample sources are compiled against both artifacts, so any signature that
    // drifts between `:olaf` and `:olaf-no-op` breaks `assembleRelease`.
    debugImplementation(project(":olaf"))
    releaseImplementation(project(":olaf-no-op"))

    implementation(libs.androidx.core.ktx)
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.foundation)
    implementation(libs.compose.material3)
    implementation(libs.androidx.activity.compose)
    debugImplementation(libs.compose.ui.tooling)
}
