#!/usr/bin/env bash
#
# Cuts a release for either platform.
#
#   scripts/release.sh ios 0.51.0
#   scripts/release.sh android 0.9.0
#   scripts/release.sh android 0.9.0 --dry-run
#
# Everything that can be checked before a tag exists is checked here, because a tag is the one
# thing that is awkward to take back once pushed. Once the tag lands, the release workflow builds
# and publishes it — see RELEASING.md.

set -euo pipefail

readonly ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; BOLD=$'\033[1m'; OFF=$'\033[0m'
die() { echo "${RED}✗ $*${OFF}" >&2; exit 1; }
ok()   { echo "${GREEN}✓${OFF} $*"; }
step() { echo; echo "${BOLD}$*${OFF}"; }

usage() {
    cat <<'EOF'
usage: scripts/release.sh <ios|android> <x.y.z> [--dry-run]

  ios       tags x.y.z          — Swift Package Manager resolves it from git
  android   tags android-x.y.z  — JitPack builds the artifacts from the tag

  --dry-run  run every check and the full verification, but do not tag or push
EOF
    exit 2
}

# ── Arguments ────────────────────────────────────────────────────────────────

[[ $# -ge 2 ]] || usage
readonly PLATFORM="$1"
readonly VERSION="$2"
DRY_RUN=false
[[ "${3:-}" == "--dry-run" ]] && DRY_RUN=true

case "$PLATFORM" in
    ios)     TAG="$VERSION";           CHANGELOG="CHANGELOG.md" ;;
    android) TAG="android-$VERSION";   CHANGELOG="Android/CHANGELOG.md" ;;
    *)       usage ;;
esac

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Version must be x.y.z, got '$VERSION'"

echo "${BOLD}Releasing $PLATFORM $VERSION${OFF}  (tag: $TAG)"
$DRY_RUN && echo "${YELLOW}dry run — nothing will be tagged or pushed${OFF}"

# ── Preflight ────────────────────────────────────────────────────────────────

step "Preflight"

branch="$(git rev-parse --abbrev-ref HEAD)"
[[ "$branch" == "main" ]] || die "On branch '$branch'; releases are cut from main."
ok "on main"

[[ -z "$(git status --porcelain)" ]] || die "Working tree is dirty. Commit or stash first."
ok "working tree clean"

git fetch --quiet --tags origin
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
    die "Tag '$TAG' already exists."
fi
ok "tag '$TAG' is free"

# The tag has to point at a commit the remote already has, or the release workflow builds
# something nobody can check out.
if [[ -n "$(git log --oneline origin/main..HEAD)" ]]; then
    die "main has unpushed commits. Push them first: git push"
fi
ok "main is in sync with origin"

# Release notes come from the CHANGELOG, so a missing section has to fail here rather than
# producing an empty GitHub Release later.
python3 scripts/changelog_section.py "$CHANGELOG" "$TAG" >/dev/null \
    || die "No '## [$VERSION]' section in $CHANGELOG. Write the changelog entry first."
ok "$CHANGELOG has a [$VERSION] section"

if [[ "$PLATFORM" == "android" ]]; then
    # Local builds use this constant; CI and JitPack override it with the tag. If they disagree,
    # a developer building locally gets a different version than the release — so they must match.
    local_version="$(sed -n 's/^private val localVersion = "\(.*\)"$/\1/p' Android/build.gradle.kts)"
    if [[ "$local_version" != "$VERSION" ]]; then
        die "Android/build.gradle.kts localVersion is '$local_version', expected '$VERSION'.
   Fix with: sed -i '' 's/localVersion = \"$local_version\"/localVersion = \"$VERSION\"/' Android/build.gradle.kts"
    fi
    ok "localVersion matches"
fi

# ── Verification ─────────────────────────────────────────────────────────────
# The same gates CI runs. Running them here means a failure costs a minute, not a bad tag.

step "Verification"

if [[ "$PLATFORM" == "ios" ]]; then
    echo "swift test…"
    swift test >/dev/null || die "swift test failed"
    ok "macOS tests"

    echo "xcodebuild (iOS)…"
    xcodebuild -scheme Olaf -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO \
        >/dev/null 2>&1 || die "iOS build failed"
    ok "iOS build"
else
    # Gradle needs a JDK; fall back to the one Android Studio ships when the shell has none.
    # `java -version` rather than `command -v java`: macOS ships a stub that resolves but fails.
    if [[ -z "${JAVA_HOME:-}" ]] && ! java -version >/dev/null 2>&1; then
        studio_jbr="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
        [[ -d "$studio_jbr" ]] || die "No JDK found. Set JAVA_HOME."
        export JAVA_HOME="$studio_jbr"
        ok "using Android Studio's JDK"
    fi

    echo "unit tests…"
    (cd Android && ./gradlew --quiet :olaf:testDebugUnitTest) || die "Android unit tests failed"
    ok "unit tests"

    # Building the sample against both artifacts is what catches a public signature that exists in
    # :olaf but not in :olaf-no-op — otherwise only a consumer's release build would find it.
    echo "artifacts + API compatibility…"
    (cd Android && ./gradlew --quiet -Pversion="$TAG" \
        :olaf:assembleRelease :olaf-no-op:assembleRelease \
        :sample:assembleDebug :sample:assembleRelease) || die "Android build failed"
    ok "both artifacts + sample against each"
fi

# ── Tag ──────────────────────────────────────────────────────────────────────

step "Tag"

if $DRY_RUN; then
    echo "${YELLOW}dry run: would tag '$TAG' and push${OFF}"
    echo
    echo "Release notes preview:"
    echo "──────────────────────"
    python3 scripts/changelog_section.py "$CHANGELOG" "$TAG"
    exit 0
fi

git tag "$TAG"
git push --quiet origin "$TAG"
ok "pushed $TAG"

echo
echo "${GREEN}${BOLD}Done.${OFF} The release workflow now verifies and publishes it:"
echo "  https://github.com/ersel95/olaf/actions"
if [[ "$PLATFORM" == "android" ]]; then
    echo
    echo "Consumers can use it once JitPack has built the tag (first request triggers the build):"
    echo "  com.github.ersel95.olaf:olaf:$TAG"
    echo "  com.github.ersel95.olaf:olaf-no-op:$TAG"
fi
