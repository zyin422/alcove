#!/usr/bin/env bash
# Publishes a Tofu release that friends' copies pick up through Sparkle.
#
#   scripts/release.sh 1.2 "What changed"   bump, build, sign, publish to axion66/tofu-releases, commit + tag
#   scripts/release.sh --dry-run            build the current version and generate an appcast locally; publishes nothing
#
# Needs: xcodegen; gh logged in as a user who can push to the releases repo; the "Accountabilibrosis Local Codesign"
# certificate and Sparkle's EdDSA key (generate_keys) in this Mac's login Keychain.
set -euo pipefail

RELEASES_REPO="axion66/tofu-releases"
DOWNLOAD_PREFIX="https://raw.githubusercontent.com/${RELEASES_REPO}/main/"

TOFU_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$TOFU_DIR"

die() { echo "release: $*" >&2; exit 1; }

BUMPED=0
STAGE=""
cleanup() {
  local status=$?
  if [ -n "$STAGE" ]; then rm -rf "$STAGE"; fi
  if [ "$status" != 0 ] && [ "$BUMPED" = 1 ]; then
    echo "release: failed after bumping the version. Undo with: git checkout -- project.yml Tofu.xcodeproj" >&2
  fi
}
trap cleanup EXIT

DRY_RUN=0
if [ "${1:-}" = "--dry-run" ]; then
  DRY_RUN=1
  shift
fi
VERSION="${1:-}"
NOTES="${2:-}"

setting() { awk -F'"' -v key="$1" '$1 ~ "^ *" key ": *$" { print $2; exit }' project.yml; }
CURRENT_VERSION="$(setting MARKETING_VERSION)"
CURRENT_BUILD="$(setting CURRENT_PROJECT_VERSION)"
[ -n "$CURRENT_VERSION" ] && [ -n "$CURRENT_BUILD" ] || die "could not read MARKETING_VERSION / CURRENT_PROJECT_VERSION from project.yml"

if [ "$DRY_RUN" = 1 ]; then
  VERSION="$CURRENT_VERSION"
  BUILD="$CURRENT_BUILD"
else
  [[ "$VERSION" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]] || die "usage: scripts/release.sh <version like 1.2> [notes]   or   scripts/release.sh --dry-run"
  [ "$VERSION" != "$CURRENT_VERSION" ] || die "$VERSION is already the current version"
  { git diff --quiet && git diff --cached --quiet; } || die "commit or stash your changes first; a release must match a commit"
  BUILD=$((CURRENT_BUILD + 1))
  BUMPED=1
  sed -i '' -E "s/^( *MARKETING_VERSION: ).*/\1\"$VERSION\"/; s/^( *CURRENT_PROJECT_VERSION: ).*/\1\"$BUILD\"/" project.yml
  xcodegen generate --quiet
fi

DERIVED="$TOFU_DIR/build/ReleaseData"
echo "release: building Tofu $VERSION ($BUILD)…"
xcodebuild -project Tofu.xcodeproj -scheme Tofu -configuration Release -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED" TOFU_RELEASE=1 clean build -quiet
APP="$DERIVED/Build/Products/Release/Tofu.app"
[ -d "$APP" ] || die "the build produced no Tofu.app"

# The zip is public: it must carry no Discord token or OpenAI key.
[ ! -e "$APP/Contents/Resources/discord.env" ] || die "the build bundled discord.env; release builds must carry no secrets"
plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$APP/Contents/Info.plist" 2>/dev/null; }
[ "$(plist CFBundleShortVersionString)" = "$VERSION" ] || die "built version is $(plist CFBundleShortVersionString), expected $VERSION"
[ "$(plist CFBundleVersion)" = "$BUILD" ] || die "built build number is $(plist CFBundleVersion), expected $BUILD"
[ -n "$(plist SUPublicEDKey)" ] || die "the built Info.plist has no SUPublicEDKey"
codesign --verify --deep --strict "$APP" || die "the code signature check failed"

GENERATE_APPCAST="$(find "$DERIVED/SourcePackages/artifacts" -path '*/bin/generate_appcast' -type f | head -n 1)"
[ -n "$GENERATE_APPCAST" ] || die "Sparkle's generate_appcast was not found under $DERIVED/SourcePackages/artifacts"

STAGE="$(mktemp -d)"
ZIP="Tofu-$VERSION.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$STAGE/$ZIP"
if [ -n "$NOTES" ]; then
  ESCAPED="$(printf '%s' "$NOTES" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g')"
  printf '<p>%s</p>\n' "$ESCAPED" > "$STAGE/Tofu-$VERSION.html"
fi

if [ "$DRY_RUN" = 1 ]; then
  RELEASES_DIR="$TOFU_DIR/build/release-dry-run"
  rm -rf "$RELEASES_DIR"
  mkdir -p "$RELEASES_DIR"
else
  RELEASES_DIR="$TOFU_DIR/build/tofu-releases"
  if ! gh repo view "$RELEASES_REPO" >/dev/null 2>&1; then
    echo "release: creating public repo $RELEASES_REPO…"
    gh repo create "$RELEASES_REPO" --public --description "Tofu app updates (Sparkle feed)" >/dev/null
  fi
  rm -rf "$RELEASES_DIR"
  gh repo clone "$RELEASES_REPO" "$RELEASES_DIR" -- --quiet
  # generate_appcast moves superseded archives into old_updates/; they don't need to be served.
  if [ ! -f "$RELEASES_DIR/.gitignore" ]; then echo "old_updates/" > "$RELEASES_DIR/.gitignore"; fi
fi

cp "$STAGE/$ZIP" "$RELEASES_DIR/"
if [ -f "$STAGE/Tofu-$VERSION.html" ]; then cp "$STAGE/Tofu-$VERSION.html" "$RELEASES_DIR/"; fi
"$GENERATE_APPCAST" --download-url-prefix "$DOWNLOAD_PREFIX" --embed-release-notes "$RELEASES_DIR"

if [ "$DRY_RUN" = 1 ]; then
  echo "release: dry run done; nothing was published. Archive and appcast: $RELEASES_DIR"
  sed -n '/<item>/,/<\/item>/p' "$RELEASES_DIR/appcast.xml"
  exit 0
fi

git add project.yml Tofu.xcodeproj
git commit --quiet -m "chore: release $VERSION"
BUMPED=0
git -C "$RELEASES_DIR" add -A
git -C "$RELEASES_DIR" commit --quiet -m "Tofu $VERSION"
git -C "$RELEASES_DIR" push --quiet origin HEAD:main \
  || die "pushing $RELEASES_REPO failed; retry with: git -C $RELEASES_DIR push origin HEAD:main && git tag v$VERSION"
git tag "v$VERSION"
echo "release: published Tofu $VERSION ($BUILD). Friends get it within a day, or via Tofu > Check for Updates…"
echo "release: the source repo was not pushed. When ready: git push && git push origin v$VERSION"
