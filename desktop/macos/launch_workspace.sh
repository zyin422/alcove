#!/usr/bin/env bash
# Demo-safe Launchpad runner. Tiling is best-effort.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FOCUS_URL="${1:-https://github.com}"
SIDECAR_URL="${2:-http://localhost:5173/launch/sidecar}"
HARD_KILL="${3:-0}"

"$ROOT/desktop/macos/focus_mode.sh" "$HARD_KILL" || true

open "$FOCUS_URL" || true
open "$SIDECAR_URL" || true

if osascript "$ROOT/desktop/macos/tile.applescript"; then
  echo "tiled two zones"
else
  echo "tiling skipped (grant Accessibility to Terminal/osascript, or use the web sidecar)"
fi
