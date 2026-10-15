# In-App Updates (Sparkle) — Design

**Date:** 2026-10-15
**Status:** Approved by user (conversation)
**Scope:** Tofu macOS app (`Tofu/`) plus a release script

## Goal

Friends who run Tofu get new versions without reinstalling:

1. Tofu checks a hosted feed once a day.
2. When a newer version exists, a small pop-up card appears in the left sidebar, directly above the **Stats** row: "Update available · Tofu 1.2" with an **Update** button and a dismiss (×) button.
3. **Update** hands off to Sparkle's standard update window (release notes → Install → relaunch). The app bundle is replaced in place; data, settings and Keychain entries stay.
4. The app menu has **Check for Updates…** for a manual check.
5. The maintainer publishes a release with one command: `Tofu/scripts/release.sh 1.2 "notes"`.

Audience: a handful of friends. No App Store, no paid Apple Developer ID.

## Non-goals

- Notarization / Developer ID signing. Friends see a Gatekeeper prompt on the very first install only.
- Silent background install (`SUAutomaticallyUpdate`). The user always clicks Update.
- Beta channels, phased rollout, delta-update tuning.
- Updating builds older than the first Sparkle-enabled release (they must be installed by hand once).

## Framework

**Sparkle 2.10.0** (`https://github.com/sparkle-project/Sparkle`, SPM, `from: "2.10.0"`), linked to the Tofu target via XcodeGen `packages:`.

How Sparkle works: the app fetches an appcast (RSS XML) listing versions; if an item's `sparkle:version` is higher than the running `CFBundleVersion`, it offers that item; it downloads the zip, verifies its EdDSA signature against `SUPublicEDKey` in Info.plist, then a helper swaps the `.app` bundle and relaunches.

## Hosting

- Public GitHub repo **`axion66/tofu-releases`** (separate from the private source repo, because Sparkle downloads without auth). Created by the release script on first run (`gh repo create --public`).
- Layout: `appcast.xml` and `Tofu-<version>.zip` (+ `Tofu-<version>.html` release notes) at the repo root; `generate_appcast` moves old archives into `old_updates/`.
- Feed URL baked into the app: `https://raw.githubusercontent.com/axion66/tofu-releases/main/appcast.xml`
- Download URL prefix: `https://raw.githubusercontent.com/axion66/tofu-releases/main/`

## Secrets: release builds carry none

The zips are publicly downloadable, so **release builds bundle no `discord.env` at all** — neither the team `.env` (Discord bot token) nor `.env.local` (personal OpenAI key). Friends enter the Discord bot token (and optionally their own OpenAI key) once in Settings; both are stored in the Keychain, which survives updates. The maintainer shares the bot token with friends privately. Dev builds from source keep bundling `.env` + `.env.local` as today.

## Info.plist keys

Added through XcodeGen `info:` (Xcode merges this file with the generated Info.plist):

| Key | Value |
|---|---|
| `SUFeedURL` | `https://raw.githubusercontent.com/axion66/tofu-releases/main/appcast.xml` |
| `SUPublicEDKey` | `my3cG5Hh9Yhc83xOkrv32Wq8IzQhgBZFE6Y7JXs7qow=` |
| `SUEnableAutomaticChecks` | `true` (no "check automatically?" prompt) |
| `SUScheduledCheckInterval` | `86400` |

The private EdDSA key lives in the maintainer's login Keychain (account `ed25519`), created with Sparkle's `generate_keys`. Back it up with `generate_keys -x <file>`; losing it means friends must reinstall by hand.

## Signing

Releases are signed with the existing self-signed identity **"Accountabilibrosis Local Codesign"** (already in `project.yml`), always from the maintainer's Mac. Same certificate on every release ⇒ macOS keeps the Accessibility and Automation grants across updates. Hardened runtime stays off.

## App architecture

```
UpdateCenter (Engine, @Observable, pure state)   ← tested with a fake driver
   ▲ callbacks                │ checkForUpdates()
   │                          ▼
SparkleUpdater (System) — owns SPUStandardUpdaterController,
   implements SPUStandardUserDriverDelegate "gentle reminders"
```

- **`UpdateDriving`** protocol (`@MainActor`): `func checkForUpdates()`.
- **`UpdateCenter`** (`@Observable @MainActor final class`), owned by `AppModel` as `let updates = UpdateCenter()`:
  - `var driver: (any UpdateDriving)?` — nil in tests and Debug builds.
  - `private(set) var availableVersion: String?` — the version shown on the card; nil = no card.
  - `var canCheckForUpdates: Bool { driver != nil }`
  - `func updateFound(version: String)` — shows the card unless `version` equals the version the user dismissed this run.
  - `func dismiss()` — hides the card and remembers its version as dismissed (in memory only; a relaunch or a newer version shows it again).
  - `func checkNow()` — used by both the card's Update button and the menu item: hides the card and calls `driver?.checkForUpdates()` (Sparkle's window takes over).
  - `func hide()` — hides the card without marking it dismissed (Sparkle got the user's attention, or its update session ended).
- **`SparkleUpdater`** (`System/SparkleUpdater.swift`): creates `SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)`; delegate:
  - `supportsGentleScheduledUpdateReminders` → `true`
  - `standardUserDriverShouldHandleShowingScheduledUpdate(_:andInImmediateFocus:)` → `false` (scheduled finds go to the card, not a window)
  - `standardUserDriverWillHandleShowingUpdate(_:forUpdate:state:)` → when `handleShowingUpdate == false`, `center.updateFound(version: update.displayVersionString)`
  - `standardUserDriverDidReceiveUserAttention(forUpdate:)` → `center.hide()`
  - `standardUserDriverWillFinishUpdateSession()` → `center.hide()`
- **Wiring** (`AppDelegate.applicationDidFinishLaunching`, already skipped under tests): in non-`DEBUG` builds create `SparkleUpdater(center: model.updates)`, retain it, set `model.updates.driver` (the center owns the updater; `SparkleUpdater` holds the center `unowned`). Debug builds never start Sparkle (a dev build must not replace itself).

## UI

**Sidebar card** (`UI/UpdateCard.swift`, shown in `SidebarView`'s bottom pinned `VStack`, first item, above the Stats row) when `model.updates.availableVersion != nil`:

```
┌──────────────────────────────┐
│ UPDATE AVAILABLE           × │   caption (Theme.captionFont, secondary), xmark button
│ Tofu 1.2                     │   13 pt semibold
│ [        Update         ]    │   SecondaryButtonStyle, full width
└──────────────────────────────┘
```

- Monochrome (spec §11 theme): hairline border `Color.primary.opacity(0.15)`, radius `Theme.radius`, padding `Theme.Space.s`, plain fill `Color(nsColor: .windowBackgroundColor)`, subtle shadow (`radius 6, y 2, opacity 0.12`) so it reads as a pop-up.
- Appears with `.transition(.move(edge: .bottom).combined(with: .opacity))`, animated `.spring(duration: 0.35)` on `availableVersion` changes.
- × has `.help("Remind me later")`; Update has `.help("Download and install Tofu <version>")`.

**Menu:** `CommandGroup(after: .appInfo) { Button("Check for Updates…") { model.updates.checkNow() }.disabled(!model.updates.canCheckForUpdates) }` — omitted under tests (the test host must not create `AppModel`).

## Build phase change

The `Bundle team .env` post-compile script bundles nothing when the build setting `TOFU_RELEASE=1` is set (it still removes any stale `discord.env`). Normal dev builds unchanged.

## Release script — `Tofu/scripts/release.sh <version> [notes]` / `--dry-run`

1. Refuse unless: run from a clean git tree (no staged/unstaged changes to tracked files), `<version>` matches `^[0-9]+(\.[0-9]+){1,2}$` and differs from the current `MARKETING_VERSION`. `--dry-run` skips the clean-tree and version checks and uses the current version.
2. Bump `MARKETING_VERSION` to `<version>` and `CURRENT_PROJECT_VERSION` to current + 1 in `project.yml`; `xcodegen generate`. (Dry run: no bump.)
3. `xcodebuild … -configuration Release TOFU_RELEASE=1 -derivedDataPath build/ReleaseData clean build`.
4. Verify: the built app has **no** `Contents/Resources/discord.env`; built `CFBundleVersion`/`CFBundleShortVersionString` match the expected values; `SUPublicEDKey` is present in the built Info.plist; `codesign --verify --deep --strict` passes. Any failure aborts before publishing.
5. Zip with `ditto -c -k --sequesterRsrc --keepParent Tofu.app Tofu-<version>.zip`; write `Tofu-<version>.html` containing `<p>notes</p>` (HTML-escaped) when notes are given.
6. Clone/pull `axion66/tofu-releases` into `build/tofu-releases` (create the GitHub repo first if `gh repo view` fails). Dry run: work in a temp directory, never touch GitHub.
7. Copy zip (+ notes) in; run Sparkle's `generate_appcast --download-url-prefix https://raw.githubusercontent.com/axion66/tofu-releases/main/ --embed-release-notes <dir>` (tool found under `build/ReleaseData/SourcePackages/artifacts`).
8. Commit + push the releases repo; commit the version bump in the source repo (`chore: release <version>`) and tag `v<version>`. Never pushes the source repo. Dry run: print the generated appcast and stop.

## README

New "Updates" section: how friends get updates, first-install Gatekeeper steps, entering the Discord token in Settings, maintainer release steps, key backup.

## Testing

- `UpdateCenterTests` (XCTest, fake driver): found → card; dismiss → hidden and the same version stays hidden; newer version re-shows; `checkNow` hides the card and call the driver once; no driver → `canCheckForUpdates == false` and `checkNow` is a no-op; `hide` does not dismiss.
- Release script: `bash -n`, then `--dry-run` end to end on the maintainer Mac (produces a signed zip and an appcast locally, publishes nothing; its verify step proves no `discord.env` ships).
