import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.dsl.KotlinAndroidProjectExtension

plugins {
    alias(libs.plugins.android.library) apply false
    alias(libs.plugins.android.application) apply false
    alias(libs.plugins.kotlin.android) apply false
    alias(libs.plugins.kotlin.compose) apply false
}

// Single source of truth for the published version — mirrored in Android/CHANGELOG.md
// and used by both publishable modules. iOS keeps its own version line (see /CHANGELOG.md).
val olafVersion by extra("0.5.0")
val olafGroup by extra("com.github.ersel95.olaf")

subprojects {
    plugins.withId("org.jetbrains.kotlin.android") {
        extensions.configure<KotlinAndroidProjectExtension> {
            compilerOptions {
                jvmTarget.set(JvmTarget.JVM_17)
                // Same bar as the iOS package: the build stays warning-free.
                allWarningsAsErrors.set(true)
            }
        }
    }
}
