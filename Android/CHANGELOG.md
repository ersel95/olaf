# Changelog — Olaf Android

The format is inspired by [Keep a Changelog](https://keepachangelog.com/en/); versioning follows
SemVer (0.x — API not yet stable). Android releases are tagged `android-x.y.z` so they stay
independent of the iOS package's own version line (see the [root CHANGELOG](../CHANGELOG.md)).

## [Unreleased]
### Added
- Gradle build skeleton: `:olaf` (library), `:olaf-no-op` (release stand-in) and `:sample`
  modules, version catalog aligned with the host app (AGP 8.12.2, Kotlin 2.1.20,
  Compose BOM 2025.09, OkHttp 5.1.0), `maven-publish` wiring for
  `com.github.ersel95.olaf:olaf` / `:olaf-no-op`, and an `android` CI job next to the iOS one.
