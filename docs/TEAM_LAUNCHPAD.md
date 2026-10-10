# Team Launchpad

**Phase:** morning / pre-session  
**Judging hook:** practicality — starting work should be one click, not a ritual.  
**Out of scope:** tab monitoring, Stuck vs Forfeit (The Mirror).

## Goal

Drop activation energy. The committed workspace is already open, references are beside it, and the blank page is pre-filled. Starting becomes editing, not creating.

## Owners

Fill names at the event. Until then, treat this doc as the queue.

- Launch UI (`/launch`)
- Sidecar (`/launch/sidecar`)
- Launch plan generator (`POST /api/launch`)
- macOS desktop scripts
- Pre-draft outline

## Build order

1. Render today's session from `GET /api/session` (tolerate empty ingest; use PUT editor).
2. Big **Launch** button → `POST /api/launch`.
3. Show launch plan: focus URL, references, apps to minimize, pre-draft markdown.
4. Sidecar route: goals, countdown, prep actions, pre-draft (Zone B).
5. `desktop/macos/launch_workspace.sh`: open focus URL + sidecar; try AppleScript tile; never hard-kill Discord/Chrome/Cursor.
6. If the browser cannot spawn processes, show the exact command to paste in Terminal.
7. Polish the happy path for the 5-minute demo.

## Desktop rules

- Default focus mode: **minimize** denylist (Steam, Messages, Twitter).
- Hard kill is a flag, default `false`.
- Tiling requires Accessibility permission and will fail on many Siebel machines. Fallback is browser tabs + sidecar.
- Script should still succeed if tiling fails.

## Done when

One click (or one terminal command) opens the work surface and a sidecar that shows today's three priorities.

## Files

- `apps/web/src/pages/Launch.tsx`
- `apps/web/src/pages/LaunchSidecar.tsx`
- `apps/api/src/launch.ts`
- `desktop/macos/launch_workspace.sh`
- `desktop/macos/tile.applescript`
- `desktop/macos/focus_mode.sh`
