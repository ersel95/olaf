# Releasing

Both platforms live in this repository but ship on **independent version lines**, so a change to
one never forces a release of the other.

| Platform | Tag | Consumed as |
|---|---|---|
| iOS | `0.51.0` (example) | Swift Package Manager resolves the tag directly from git |
| Android | `android-0.11.0` (example) | JitPack builds the artifacts from the same tag |

`android-*` tags are not semver, so SPM ignores them entirely — the iOS version line stays clean
no matter how often Android ships.

## The procedure

Releasing is **tag-driven**. Everything after the tag is automated by
[`.github/workflows/release.yml`](.github/workflows/release.yml):

1. Update the relevant `CHANGELOG.md` with a `## [x.y.z] — YYYY-MM-DD` section.
   For Android, also bump `localVersion` in `Android/build.gradle.kts` so local builds match.
2. Commit.
3. Tag and push:

   ```bash
   git tag 0.51.0        && git push --tags   # iOS
   git tag android-0.11.0 && git push --tags   # Android
   ```

The workflow then:

- **verifies before publishing** — `swift test` + iOS build, or the Android unit tests plus both
  artifacts *and* the sample compiled against each of them (the API-compatibility gate). A tag that
  doesn't build never becomes a release;
- **writes the release notes from the CHANGELOG** via
  [`scripts/changelog_section.py`](scripts/changelog_section.py), so notes can't drift from the
  changelog — a missing section fails the release rather than publishing empty notes;
- **attaches the AARs** to Android releases.

Nothing is published by hand, and no credentials are needed: the workflow uses the repository's
own token.

## How Android consumers get it

JitPack builds the tag on first request; no publishing infrastructure, no accounts, no secrets.

```kotlin
// settings.gradle.kts
dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
        maven { url = uri("https://jitpack.io") }
    }
}
```

```kotlin
// build.gradle.kts of the module that owns your OkHttpClient
debugImplementation("com.github.ersel95.olaf:olaf:android-0.10.0")
releaseImplementation("com.github.ersel95.olaf:olaf-no-op:android-0.10.0")
```

The version is the tag itself, so it is always obvious which commit an artifact came from.

`Android/build.gradle.kts` takes the version from `-Pversion` when one is passed (which is what
JitPack does with the tag) and falls back to the local constant otherwise — so a release requires
no edit to the build file beyond the changelog bump.

### Working against an unreleased change

```bash
cd Android && ./gradlew publishToMavenLocal
```

then add `mavenLocal()` to the consumer's repositories. Same coordinates, so switching back to a
released version is a one-line change.

## If this ever outgrows JitPack

The move to Maven Central is a workflow change, not an architectural one: add a `publish` job with
the Sonatype credentials and signing key. The one thing that changes for consumers is the group,
since Central requires a verified namespace (`io.github.ersel95` rather than
`com.github.ersel95.olaf`) — worth doing at a major version, not mid-stream.

## Version-line rules

- Tag when sources change. Documentation-only changes are not tagged.
- SemVer, `0.x` while the API is still settling.
- The Android `CHANGELOG` version and the tag must match — the release fails otherwise, which is
  the point.
