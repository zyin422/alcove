# Google Tasks + Calendar Sync — Design

**Date:** 2026-10-15
**Status:** Approved by user (conversation), pending spec review
**Scope:** Tofu macOS app (`Tofu/Tofu`)

## Goal

Connect Tofu to the user's Google account so that:

1. Today's day plan mirrors the user's default Google Tasks list (two-way).
2. Completed focus sessions are logged as events in a dedicated "Tofu" Google Calendar.
3. Today's calendar events (meetings, classes) are shown read-only in the Morning screen and Today view.
4. Checking off a priority in Tofu marks the Google task complete, and vice versa.

Single-user, personal use. Reuses the existing Desktop OAuth client from the
`uiuc_collective_mind` project (`~/coding/uiuc/uiuc_collective_mind/lib/google/auth.mjs`),
which already has the Tasks and Calendar scopes configured on its Google Cloud project.

## Non-goals

- Multiple Google accounts, multiple task lists, or task list selection UI.
- Offline operation queue; Tofu assumes the Mac is generally online.
- Editing calendar events from Tofu (pull is read-only).
- Historical backfill of past sessions into Calendar.

## Architecture

New module `Tofu/Tofu/Engine/Google/` with three units, following the Discord
integration's existing patterns (Keychain for secrets, `HTTPTransport` seam for tests):

```
GoogleAuth   — OAuth 2.0 PKCE flow, token lifecycle, Keychain persistence
GoogleClient — thin REST client for Tasks API + Calendar API
GoogleSync   — merge engine: polls, diffs, applies changes both directions
```

Plus small touches: `Priority.googleTaskID`, `AppSettings` toggles,
`SettingsView` Google section, `SessionEngine` end-of-session hook,
Morning screen / Today view event display.

### 1. GoogleAuth

- Constants: client ID `727798165808-vkh1rujb994drot1gp3k5rk2jrmci23m.apps.googleusercontent.com`
  and its client secret, copied from the uiuc project. This is a **Desktop** OAuth client:
  per RFC 8252 its secret is not confidential, and the flow is protected by PKCE.
- Scopes: `https://www.googleapis.com/auth/tasks`,
  `https://www.googleapis.com/auth/calendar.events`,
  `https://www.googleapis.com/auth/calendar` (the full calendar scope is required to
  create and list calendars for the dedicated "Tofu" calendar).
- Connect flow:
  1. Generate PKCE verifier (32 random bytes, base64url) + S256 challenge + random state.
  2. Start `NWListener` on `127.0.0.1` with an ephemeral port; redirect URI is
     `http://127.0.0.1:<port>`.
  3. Open the browser (`NSWorkspace.shared.open`) at
     `https://accounts.google.com/o/oauth2/v2/auth` with
     `access_type=offline&prompt=consent` so a refresh token is always returned.
  4. Loopback listener receives the callback, validates `state`, responds with a
     minimal "You're connected — close this tab" HTML page, and stops.
  5. Exchange the code at `https://oauth2.googleapis.com/token` with the verifier
     and client secret. A missing `refresh_token` is an error (message tells the
     user to remove the app at myaccount.google.com/permissions and retry).
- Storage: refresh token in the **Keychain** (same approach as the Discord bot token;
  separate service name for Google). Access token and expiry held in memory only,
  refreshed on demand with a 60-second skew.
- Dead-token handling: a refresh that fails with `invalid_grant`,
  `unauthorized_client`, `invalid_client`, or `deleted_client` disconnects
  (deletes the Keychain entry) so Settings shows a Connect button instead of a
  recurring error. Any other error is transient and surfaces as a sync failure.
- Disconnect: delete the Keychain entry and drop in-memory tokens.

### 2. GoogleClient

- Reuses the `HTTPTransport` protocol currently declared in `DiscordClient.swift`;
  that protocol (and `URLSessionTransport`) moves to its own shared file so both
  clients use it. Tests script responses through it exactly as Discord tests do.
- Endpoints:
  - Tasks (`https://tasks.googleapis.com/tasks/v1`), default list (`@default`):
    `listTasks(showCompleted:)`, `insertTask(title:due:)`,
    `patchTask(id:title:status:)`, `deleteTask(id:)`.
  - Calendar (`https://www.googleapis.com/calendar/v3`):
    `listCalendars()`, `insertCalendar(summary: "Tofu")`,
    `insertEvent(calendarID:summary:description:start:end:)`,
    `listEvents(calendarID:from:to:)` for today's window.
- Every request carries a fresh access token from `GoogleAuth`. On a 401 the client
  forces one token refresh and retries once.
- `GoogleError` enum mirrors `DiscordError`: `.http(Int)`, `.transport(String)`,
  `.decoding`, plus `.notConnected`.

### 3. GoogleSync (task mirror)

- `Priority` gains `var googleTaskID: String?`, decoded with the existing
  fall-back-to-default pattern so older store files still load.
- Mirror rule: **today's day plan mirrors the default Google Tasks list.**
  - Pull: every incomplete task in the list appears as a priority in today's plan
    (upsert by `googleTaskID`; title and done state follow Google). Tasks completed
    today appear as done priorities. Tasks completed before today are ignored.
  - Push: a priority created in Tofu without a `googleTaskID` is inserted as a task
    (due date = today) and the returned ID stored. Toggling done state in Tofu
    patches the task's `status`. Deleting a priority in Tofu deletes the task.
  - A task deleted in Google removes its mirrored (not-done) priority.
  - Conflicts: Google wins on pull; no etag/updated-time tracking in v1. Local
    mutations are pushed immediately, then the next pull reconciles.
- Cadence: full sync on connect, on app becoming active, every 60 seconds while
  running, and immediately after any local mutation of today's priorities.
- The sync cycle runs when connected and at least one Google toggle is on; within a
  cycle, task mirroring, event pull, and pending event push each run only when their
  own toggle is on.

### 4. Calendar push + pull

- Push: when a session ends with outcome `completed`, or `bailed` with duration
  ≥ 5 minutes, insert an event into the dedicated "Tofu" calendar:
  - summary `Focus: <subjectName>`, real start/end times,
  - description includes mode (open/goal), outcome, blocked attempts, closed tabs.
  - Demo sessions (`isDemo`) are never pushed.
- The "Tofu" calendar is found by summary in `listCalendars()` or created on first
  use; its ID is cached in `AppSettings.googleCalendarID`. If the cached ID turns
  out deleted (404), re-find/re-create once.
- Pull: today's events (4 AM day window is NOT used here — calendar day is
  midnight-to-midnight local) from every calendar the user has `selected == true`
  in their Google calendar list, excluding the Tofu calendar itself. Held in
  memory on `AppModel`; refreshed on the same cadence as the sync cycle.
- Display: a read-only "Today's events" list (time + title) in the Morning screen
  and the Today view. No editing, no event detail UI.

### 5. Settings & app wiring

- `AppSettings` additions (all with codable fall-backs):
  - `googleTasksSyncEnabled: Bool = true`
  - `googleSessionLogEnabled: Bool = true`
  - `googleShowEventsEnabled: Bool = true`
  - `googleCalendarID: String?`
- `SettingsView` gains a "Google" section: connection status, Connect/Disconnect
  button, and the three toggles (disabled while disconnected).
- `AppModel` owns `GoogleAuth`/`GoogleClient`/`GoogleSync` instances and exposes
  connection state + today's events to the UI.
- `SessionEngine` calls the calendar push hook where it already finalizes sessions.

### 6. Error handling

- All sync and push failures are non-fatal: log, show one toast (via the existing
  `ToastCenter`) on the first consecutive failure, retry on the next cycle.
- Auth failures that kill the refresh token flip the UI back to "Connect".
- No retry storms: one in-flight sync at a time; a failed calendar event push for a
  session is retried on the next sync cycle until it succeeds (pending event kept
  in memory; losing it on app quit is acceptable in v1).

### 7. Testing

Following the existing test style (`TofuTests`, scripted transports, pure logic):

- `GoogleAuthTests` — auth URL parameters (PKCE challenge, state, scopes, offline
  access), token exchange, refresh skew, dead-token disconnect, Keychain round-trip
  faked through a protocol.
- `GoogleClientTests` — request shapes and decoding for each endpoint via scripted
  `HTTPTransport`; 401-refresh-retry behavior.
- `GoogleSyncTests` — pure merge logic: pull upserts, push of unlinked priorities,
  done-state propagation both ways, deletions both ways, completed-before-today
  ignored.
- `CompanionSettingsTests`-style codable migration tests for the new `AppSettings`
  fields and `Priority.googleTaskID`.

## Known caveats (accepted)

- The Google consent screen belongs to "UIUC Collective Mind", so that name shows
  during sign-in.
- If that Google Cloud project's consent screen is still in **Testing** mode,
  Google expires refresh tokens after 7 days — reconnect weekly, or publish the
  consent screen once in that project's console. The dead-token handling above
  makes this a one-click reconnect.
- Google Tasks due dates are date-only; times are not synced.
