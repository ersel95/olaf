plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    `maven-publish`
}

android {
    namespace = "com.olaf"
    compileSdk = 36

    defaultConfig {
        minSdk = 26
        consumerProguardFiles("consumer-rules.pro")
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
    }

    publishing {
        // A single `release` component keeps the published POM as simple as the
        // iOS package's single SPM product.
        singleVariant("release") {
            withSourcesJar()
        }
    }

    testOptions {
        unitTests.isReturnDefaultValues = true
    }
}

dependencies {
    // `api` (not `implementation`): consumers pass an OkHttp `Interceptor` to their own
    // client, so the OkHttp types are part of Olaf's public surface.
    api(libs.okhttp)

    implementation(libs.androidx.core.ktx)
    implementation(libs.coroutines.android)

    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.foundation)
    implementation(libs.compose.material3)
    implementation(libs.compose.material.icons)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    debugImplementation(libs.compose.ui.tooling)
    implementation(libs.compose.ui.tooling.preview)

    testImplementation(libs.junit)
    testImplementation(libs.json)
    testImplementation(libs.coroutines.test)
}

publishing {
    publications {
        register<MavenPublication>("release") {
            groupId = rootProject.extra["olafGroup"] as String
            artifactId = "olaf"
            version = rootProject.extra["olafVersion"] as String

            afterEvaluate {
                from(components["release"])
            }

            pom {
                name.set("Olaf")
                description.set("On-device network logger & log viewer for Android.")
                url.set("https://github.com/ersel95/olaf")
                licenses {
                    license {
                        name.set("MIT License")
                        url.set("https://github.com/ersel95/olaf/blob/main/LICENSE")
                    }
                }
                developers {
                    developer {
                        id.set("ersel95")
                        name.set("Ersel Tarhan")
                    }
                }
                scm {
                    url.set("https://github.com/ersel95/olaf")
                }
            }
        }
    }
}
