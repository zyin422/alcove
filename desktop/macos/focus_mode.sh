#!/usr/bin/env bash
# Minimize denylisted apps. Never target Discord, Chrome, or Cursor.
set -euo pipefail
HARD_KILL="${1:-0}"
DENYLIST=("Steam" "Messages" "Twitter" "X")

for app in "${DENYLIST[@]}"; do
  if [[ "$HARD_KILL" == "1" ]]; then
    osascript -e "tell application \"$app\" to quit" 2>/dev/null || true
  else
    osascript -e "tell application \"System Events\" to set visible of process \"$app\" to false" 2>/dev/null || true
  fi
done
echo "focus mode applied (hardKill=$HARD_KILL)"
