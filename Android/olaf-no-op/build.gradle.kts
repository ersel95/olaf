plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.android)
    `maven-publish`
}

// The release counterpart of `:olaf` — same public API surface, empty bodies.
// Consumers wire it up exactly like Chucker does:
//   debugImplementation("com.github.ersel95.olaf:olaf:x.y.z")
//   releaseImplementation("com.github.ersel95.olaf:olaf-no-op:x.y.z")
// so no Olaf code (and no viewer, no capture) reaches the production APK.
android {
    namespace = "com.olaf.noop"
    compileSdk = 36

    defaultConfig {
        minSdk = 26
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    publishing {
        singleVariant("release") {
            withSourcesJar()
        }
    }
}

dependencies {
    // Only OkHttp: the no-op still has to hand back a real (pass-through) Interceptor.
    api(libs.okhttp)
}

publishing {
    publications {
        register<MavenPublication>("release") {
            groupId = rootProject.extra["olafGroup"] as String
            artifactId = "olaf-no-op"
            version = rootProject.extra["olafVersion"] as String

            afterEvaluate {
                from(components["release"])
            }

            pom {
                name.set("Olaf No-Op")
                description.set("No-op variant of Olaf for release builds.")
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
