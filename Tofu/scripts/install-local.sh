#!/usr/bin/env bash
# Builds the local Tofu binary and installs it to ~/Applications/Tofu.app
# Relaunches Tofu if running so the live daemon runs current code.

set -euo pipefail

TOFU_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$TOFU_DIR"

INSTALL_DIR="$HOME/Applications"
TARGET_APP="$INSTALL_DIR/Tofu.app"

RESTART=1
if [ "${1:-}" = "--no-restart" ]; then
  RESTART=0
fi

ARCH="$(uname -m)"
echo "==> Building Tofu (Release for $ARCH)..."
xcodebuild -project Tofu.xcodeproj -scheme Tofu -configuration Release -destination "platform=macOS,arch=$ARCH" build -quiet

TARGET_BUILD_DIR="$(xcodebuild -project Tofu.xcodeproj -scheme Tofu -configuration Release -destination "platform=macOS,arch=$ARCH" -showBuildSettings 2>/dev/null | awk -F' = ' '$1 ~ /TARGET_BUILD_DIR/ { print $2; exit }')"
FULL_PRODUCT_NAME="$(xcodebuild -project Tofu.xcodeproj -scheme Tofu -configuration Release -destination "platform=macOS,arch=$ARCH" -showBuildSettings 2>/dev/null | awk -F' = ' '$1 ~ /FULL_PRODUCT_NAME/ { print $2; exit }')"

BUILT_APP="${TARGET_BUILD_DIR}/${FULL_PRODUCT_NAME}"
if [ ! -d "$BUILT_APP" ]; then
  echo "Error: Build succeeded but $BUILT_APP not found." >&2
  exit 1
fi

echo "==> Verifying signature..."
codesign --verify --deep --strict "$BUILT_APP"

echo "==> Installing to $TARGET_APP..."
mkdir -p "$INSTALL_DIR"
WAS_RUNNING=0
if pgrep -x Tofu >/dev/null 2>&1; then
  WAS_RUNNING=1
fi

TMP_APP="$INSTALL_DIR/Tofu.tmp.$$.app"
rm -rf "$TMP_APP"
ditto "$BUILT_APP" "$TMP_APP"
rm -rf "$TARGET_APP"
mv "$TMP_APP" "$TARGET_APP"

echo "==> Installed successfully: $TARGET_APP"

if [ "$WAS_RUNNING" = 1 ] && [ "$RESTART" = 1 ]; then
  echo "==> Relaunching Tofu with updated binary..."
  pkill -x Tofu || true
  sleep 1
  open -g "$TARGET_APP"
fi
