# Tofu — macOS Lock-In App: Design Spec

- **Date:** 2026-10-10
- **Status:** Approved design. This spec is pending written review.
- **Context:** Code Ada 2026 (Off the Clock track). Submissions are due **2026-10-10 23:59 CDT**. The build has to fit in ~7 hours.
- **Approach:** a single native SwiftUI app that does everything in-process (approach "A").

---

## 1. Goal

When the user clicks **Lock in** on a subject (e.g. "CS128"), the Mac turns into a focus environment:

1. Every other app gets out of the way.
2. Chrome opens the subject's pre-configured sites in a pre-chosen layout.
3. Distracting apps and sites are pushed away the moment they appear.
4. Friends in Discord see that the user is locked in.
5. The app tracks lock-in time and shows it back as a giant timer and as statistics.

**Success criteria for the demo:**

1. Create subject "CS128" with two sites and the left/right layout.
2. Click Lock in. All other apps vanish, the two Chrome windows tile left and right, and the mini timer is visible.
3. A Discord server channel receives "🔒 Alex is locked in on CS128".
4. Opening Discord or Notes makes it vanish instantly. A top-right toast appears and the attempt counter goes up.
5. Opening youtube.com in Chrome closes that tab and shows a toast.
6. Ending early asks the user to type the give-up phrase. Discord then receives the "bailed" message.
7. Previously hidden apps come back.
8. Stats show bars for day, week and month, plus summary numbers. Demo seed data makes them look full.

**Users:** one person on one Mac (demo). There are no accounts and no sync.

## 2. Decisions (from the Q&A)

| Topic | Decision |
|---|---|
| Stack | Swift 6.1 toolchain in **Swift 5 language mode**, SwiftUI with AppKit bridges, macOS 14+ deployment target, Xcode 16.3 |
| Project | XcodeGen `project.yml`. The generated `.xcodeproj` is committed so teammates can just open it. |
| Clearing apps at lock-in | **Hide**, never quit. When the session ends, unhide the apps we hid. |
| Disallowed app during session | **Hide** it, show a top-right toast, and count the attempt. |
| Session modes | **Open-ended** (count up) or **goal** (count down: 25/50/90 minutes or custom). The user picks when locking in. |
| Early quit | Allowed only in goal mode before the goal is reached. The user must type the give-up phrase (friction). It is then announced on Discord as a bail. |
| Discord | The app calls the Discord REST API directly with a bot token kept in the Keychain (entered by the user). It posts to one channel per guild the bot is in. **Group DMs are impossible for bots** (official docs). |
| Discord messages | Start, completion (duration, app attempts, closed tabs) and bail. |
| Layout presets | Four presets: left/right halves, full, thirds (app \| Chrome \| Chrome), 70/30 (Chrome \| app) |
| Chrome site blocking | While locked in, close tabs whose host is outside the allowed domains. |
| Stats | Day/week/month bar charts, per-subject breakdown, streak, session count, average and longest session, app attempts, closed tabs, bails |
| Persistence | A local JSON file in Application Support |
| Notifications | A custom black/white top-right **toast panel**, not UNUserNotificationCenter. This avoids notification permission prompts and Focus/DND suppression, and keeps the theme. |
| Theme | Monochrome black and white. It follows the system appearance (light: white background; dark: black background). Grays only. No accent color. |
| Old repo leftovers | Deleted (web monorepo and GrokBot docs). The PDFs are kept. |

## 3. Hard platform constraints (researched)

- **No pre-launch blocking.** On macOS, Screen Time APIs (FamilyControls/ManagedSettings) are unavailable. Endpoint Security needs an entitlement that Apple must approve. So we detect a launch or activation, then hide. A brief flash of the app (~100–300 ms) is unavoidable.
- **Must be unsandboxed.** `NSRunningApplication.terminate()`/`hide()` of other apps does not work from the App Sandbox. That rules out the App Store. A local ad-hoc-signed build is fine.
- **Discord bots cannot join group DMs** ("Bots cannot have friends or be added to or join Group DMs", from the Discord OAuth2 docs). We post to guild text channels only.
- **Chrome AppleScript cannot choose a profile.** `make new window` fails while Chrome has no profile loaded (just after a cold launch, or while the profile picker is open). We retry.
- **Automation (TCC) prompt.** The first time we send Apple Events to Chrome, macOS shows "Tofu wants to control Google Chrome". It appears once, and Info.plist needs `NSAppleEventsUsageDescription`. We do **not** use System Events, and we do **not** need Accessibility permission.
- **The user can always escape** by quitting our app. Blocking lives in-process. We accept this for the demo.
- **Main display only.** Other Spaces, other apps' full-screen windows and Stage Manager are not handled.

## 4. Architecture

A single macOS app target plus a unit-test target. Each unit has one purpose. The pure units (marked ⚙︎) have no AppKit dependencies and are unit-tested.

```
Tofu/                      (repo subfolder)
  project.yml                            XcodeGen spec
  Tofu.xcodeproj/          generated, committed
  Tofu/
    App/
      TofuApp.swift        @main, WindowGroup + Settings scene, AppModel injection
      AppModel.swift                     @Observable root: subjects, sessions, settings, SessionEngine
    Models/
      Subject.swift                      Subject, LayoutPreset, AllowedApp
      Session.swift                      Session, SessionMode, SessionOutcome
      AppSettings.swift                  display name, discord enabled, give-up template, channel cache
    Persistence/
      Store.swift                        JSON load/save (atomic) of StoreData; heartbeat
      Keychain.swift                     get/set/delete bot token (generic password)
    Engine/
      LayoutEngine.swift          ⚙︎     preset + visibleFrame → window frames
      DomainMatcher.swift         ⚙︎     URL → allowed? given allowed domains
      StatsEngine.swift           ⚙︎     sessions → buckets, totals, streak, counts
      SessionEngine.swift                state machine; orchestrates System + Discord + Store
    System/
      WorkspaceController.swift          hide/unhide other apps; allowlist resolution
      AppBlocker.swift                   NSWorkspace observers → hide + count
      ChromeController.swift             AppleScript: open/tile windows, poll & close tabs, minimize/restore old windows
      ScreenGeometry.swift               NSScreen.visibleFrame → Chrome coordinate space
    Discord/
      DiscordClient.swift                REST calls (guilds, channels, post), 429 handling
      DiscordMessages.swift       ⚙︎     message text formatting
      ChannelPicker.swift         ⚙︎     choose channel from guild channel list
    UI/
      Theme.swift                        colors, fonts, spacing, button styles
      RootView.swift                     NavigationSplitView: sidebar + detail
      SidebarView.swift                  subjects list, "+", Stats, Settings
      SubjectDetailView.swift            subject summary + LOCK IN + subject stats
      SubjectEditorView.swift            name, preset picker, site URLs, allowed apps, extra domains
      AppPickerView.swift                pick apps from /Applications (icon + name)
      LockInSheet.swift                  choose mode: open-ended / 25 / 50 / 90 / custom
      LockedView.swift                   giant timer, subject, counters, End button
      GiveUpSheet.swift                  type phrase to bail
      MiniTimerPanel.swift               floating NSPanel (top-center) for split/full presets
      ToastCenter.swift                  top-right floating NSPanel toasts, queue + auto-dismiss
      StatsView.swift                    range toggle, bar chart, summary cards, per-subject breakdown
      SettingsView.swift                 name, Discord token/test, give-up phrase, permissions status, demo data
    Resources/
      Info.plist, Assets.xcassets
  TofuTests/
    LayoutEngineTests.swift, DomainMatcherTests.swift, StatsEngineTests.swift,
    DiscordMessagesTests.swift, ChannelPickerTests.swift, StoreTests.swift
```

**Build settings:**

| Setting | Value |
|---|---|
| `PRODUCT_BUNDLE_IDENTIFIER` | `com.tofu.app` |
| `ENABLE_APP_SANDBOX` | `NO` (no sandbox entitlements file) |
| `ENABLE_HARDENED_RUNTIME` | `NO` |
| `CODE_SIGN_IDENTITY` | `-` (ad-hoc) |
| `MACOSX_DEPLOYMENT_TARGET` | `14.0` |
| `SWIFT_VERSION` | `5.0` |
| `INFOPLIST_KEY_NSAppleEventsUsageDescription` | "Tofu opens and arranges your study sites in Google Chrome and closes off-topic tabs while you're locked in." |

**Concurrency:** all controllers and the engine are `@MainActor`. Discord networking uses `async`/`await` on `URLSession`. The AppleScript calls (`NSAppleScript`) run on the main actor; they are short. Tab polling every 2 s is acceptable for the demo. If it stutters, move it to a serial background queue with its own `NSAppleScript` instance.

## 5. Data model

```swift
enum LayoutPreset: String, Codable, CaseIterable {
  case split      // Chrome | Chrome            (2 sites) + mini timer
  case full       // Chrome                     (1 site)  + mini timer
  case thirds     // App | Chrome | Chrome      (2 sites)
  case mainSide   // Chrome 70% | App 30%       (1 site)
  var siteCount: Int { self == .split || self == .thirds ? 2 : 1 }
  var appHasZone: Bool { self == .thirds || self == .mainSide }
}

struct AllowedApp: Codable, Hashable { var bundleID: String; var name: String }

struct Subject: Codable, Identifiable, Hashable {
  var id: UUID
  var name: String                 // "CS128"
  var preset: LayoutPreset
  var sites: [String]              // length == preset.siteCount; normalized to https:// if scheme missing
  var allowedApps: [AllowedApp]    // in addition to the always-allowed set
  var extraDomains: [String]       // e.g. ["piazza.com", "stackoverflow.com"]
  var createdAt: Date
}

enum SessionMode: Codable, Hashable { case open; case goal(minutes: Int) }
enum SessionOutcome: String, Codable { case completed, bailed, interrupted }  // interrupted = app quit/crash

struct Session: Codable, Identifiable, Hashable {
  var id: UUID
  var subjectID: UUID
  var subjectName: String          // snapshot, survives subject rename/delete
  var mode: SessionMode
  var start: Date
  var end: Date?                   // nil while active
  var lastHeartbeat: Date
  var blockedAttempts: Int
  var closedTabs: Int
  var outcome: SessionOutcome?
  var isDemo: Bool                 // seeded demo data
  var duration: TimeInterval { (end ?? lastHeartbeat).timeIntervalSince(start) }
}

struct AppSettings: Codable {
  var displayName: String = NSFullUserName()
  var discordEnabled: Bool = false
  var giveUpTemplate: String = "I give up on {subject}"
  var channelCache: [String: String] = [:]   // guildID → channelID that last succeeded
}

struct StoreData: Codable { var subjects: [Subject]; var sessions: [Session]; var settings: AppSettings }
```

- **File location:** `~/Library/Application Support/Tofu/store.json`. Writes are atomic (`.atomic`), with a `version: 1` field.
- **When we save:** after every mutation, and on heartbeat.
- **Bot token:** stored in the Keychain, never in JSON. Generic password, service `com.tofu.discord`, account `bot-token`.

## 6. Session lifecycle (SessionEngine)

States: `idle` → `locked(sessionID)` → `idle`.

**Lock in** (`start(subject, mode)`):

1. Create the `Session` (`end = nil`) and save it.
2. **WorkspaceController.hideOthers(allowed:)**
   - For each `NSWorkspace.shared.runningApplications` entry with `activationPolicy == .regular`, whose bundle ID is not in the allowed set and which is not already hidden:
     - call `hide()`
     - record the bundle ID in `hiddenByUs`
   - Allowed set = always-allowed {own bundle ID, `com.google.Chrome`, `com.apple.finder`} ∪ the subject's allowed apps.
3. **ChromeController.prepare(subject, frames)**
   1. Launch or activate Chrome (`NSWorkspace.openApplication`).
   2. Minimize the Chrome windows that already exist, and remember their ids.
   3. For each site: `make new window`, set the URL of its active tab, set `bounds` to the frame from LayoutEngine. Retry up to 3× with a 1 s gap if the profile is not ready.
   4. Remember the created window ids.
4. **Position our app.**
   - If `preset.appHasZone`: set the main window frame to the app zone and show `LockedView` (giant timer).
   - Otherwise: order out the main window and show `MiniTimerPanel` (top-center, floating, non-activating, ~240×64 pt, draggable).
5. **AppBlocker.start(allowed:)** and **ChromeController.startTabWatch(allowedDomains:)**.
6. Start the 1 s UI tick and the 30 s heartbeat (update `lastHeartbeat`, then save).
7. **Discord.** If enabled, fire and forget `post(start message)`.

**During the session:**

- **AppBlocker** observes `NSWorkspace.shared.notificationCenter`: `didLaunchApplicationNotification` and `didActivateApplicationNotification`.
  - If the app is `.regular` and not in the allowed set: call `hide()`, then re-activate Chrome (or our window).
  - Count an attempt unless the same bundle ID was counted within the last 2 s (debounce, because launch plus activate fire together).
  - Toast: "🔒 Discord is blocked during CS128".
- **Tab watch** runs every 2 s. One AppleScript returns `{windowId, tabIndex, URL}` for every tab of every Chrome window.
  - For each URL where `DomainMatcher.isAllowed` is false: close that tab, iterating tabs in reverse within each window. Then `closedTabs += 1` and toast "Closed youtube.com — not part of CS128".
  - If a window loses its last allowed tab, Chrome closes the window. That is acceptable.
- **The giant timer** shows elapsed time (open mode) or remaining time (goal mode).
- In goal mode, when the remaining time reaches 0, end with `completed` automatically.

**End** (`end(outcome)`):

| Outcome | Trigger |
|---|---|
| `completed` | open mode: the user clicks End and confirms. Goal mode: the goal is reached (End is allowed without friction once the goal has passed). |
| `bailed` | goal mode before the goal: the user clicks End, the `GiveUpSheet` appears, and the user types the exact phrase (case-insensitive, whitespace-trimmed). The phrase is the template with `{subject}` replaced. |

Then, in order:

1. Stop AppBlocker, tab watch, timers.
2. Set `session.end = now` and `outcome`, then save.
3. **WorkspaceController.restore()**: `unhide()` each app in `hiddenByUs` that is still running.
4. Chrome: un-minimize the windows we minimized. **Leave the study windows open.**
5. Close MiniTimerPanel. Restore the main window to its pre-lock frame and show the session summary.
6. **Discord.** If enabled, fire and forget the completion or bail message.

**Crash or quit recovery.** On launch, any session with `end == nil` is finalized:

- `end = lastHeartbeat`
- `outcome = .interrupted`

No Discord message is sent, and we do not try to unhide anything (we have no record of what was hidden). If the user quits our app mid-session (Cmd+Q), `applicationWillTerminate` runs `end(.interrupted)` synchronously, which restores hidden apps. The Discord message is skipped because it is async.

## 7. Layout engine

**Inputs:**

- `preset`
- `visible`: `NSScreen.main!.visibleFrame` (excludes the menu bar and Dock), in Cocoa coordinates

**Outputs:**

- `chromeFrames: [CGRect]` (count = `preset.siteCount`)
- `appFrame: CGRect?`

| Preset | Zones (left → right, full height) |
|---|---|
| `split` | Chrome 0.5 · Chrome 0.5 |
| `full` | Chrome 1.0 |
| `thirds` | App ⅓ · Chrome ⅓ · Chrome ⅓ |
| `mainSide` | Chrome 0.7 · App 0.3 |

**Rounding.** Widths are rounded to whole points. The last zone absorbs any remainder, so the zones exactly cover `visible.width`.

**ScreenGeometry** converts Cocoa rects (origin bottom-left of the primary screen) into Chrome AppleScript `bounds` `{left, top, right, bottom}` (origin top-left of the primary screen, y going down):

- `top = primaryHeight − rect.maxY`
- `bottom = primaryHeight − rect.minY`
- `left = rect.minX`, `right = rect.maxX`

`primaryHeight` = `NSScreen.screens[0].frame.height`.

## 8. Domain matching

**Allowed domains** = hosts of the subject's `sites` ∪ `extraDomains`, normalized:

- lowercased
- leading `www.` stripped
- trailing dots stripped

`isAllowed(url)`:

- **true** for `chrome://newtab`, `chrome://new-tab-page`, `about:blank` and empty strings, so a blank new tab is not killed while the user types.
- **true** for other `chrome://` and `chrome-extension://` URLs. We don't fight Chrome internals.
- **true** if the URL cannot be parsed.
- **true** if the host (normalized) equals an allowed domain or ends with `"." + domain`.
- **false** otherwise.

Example: site `https://www.youtube.com/watch?v=x` allows all of youtube.com. That is acceptable; the user picked it.

## 9. Discord

**Requests** (`https://discord.com/api/v10`, header `Authorization: Bot <token>`, `User-Agent: DiscordBot (tofu, 1.0)`):

- `GET /users/@me` (the "Test connection" button: shows the bot username)
- `GET /users/@me/guilds`
- `GET /guilds/{guild.id}/channels`
- `POST /channels/{channel.id}/messages` with `{"content": …, "allowed_mentions": {"parse": []}}`

**ChannelPicker** (pure). Given a guild's channels, return an ordered list of candidates:

1. The cached channel ID for this guild, if it is still present.
2. Text channels (`type == 0`) named `lock-in`, `locked-in`, `lockin` or `accountability`, in that order.
3. All remaining text channels sorted by `position`.

**post(message)**, for each guild:

- Try candidates in order. On 403 (missing access), try the next candidate. Stop after 5 tries per guild.
- On success, cache `guildID → channelID` in settings.
- On **429**, wait `retry_after` seconds once, then retry.
- Guilds are processed sequentially. Errors are collected; if every guild fails, show one toast: "Discord: couldn't post (check bot token/permissions)".
- Never throw into the session flow.

**Bot invite (documented in the README):** `https://discord.com/oauth2/authorize?client_id=<APP_ID>&scope=bot&permissions=3072` (View Channel + Send Messages).

**Messages** (`DiscordMessages`, pure). `name` = settings display name; durations are formatted `1h 20m` or `12m` (rounded down to minutes, minimum `0m`):

- **start:** `🔒 **{name}** is locked in on **{subject}**`, followed by ` (goal {goal})` in goal mode
- **completed:** `✅ **{name}** locked in on **{subject}** for **{duration}** · tried other apps **{attempts}×** · closed **{tabs}** tabs`
- **bailed:** `🏳️ **{name}** bailed on **{subject}** after **{duration}** (goal {goal}) · tried other apps **{attempts}×**`

## 10. Statistics (StatsEngine, pure)

**Rules:**

- Sessions are attributed to the local calendar day of `start`. Sessions spanning midnight are not split; that is a known simplification.
- Durations come from `Session.duration`.
- All outcomes count toward time. `interrupted` counts up to its last heartbeat.

**Ranges** (toggle in StatsView). Each bar shows total minutes, stacked by subject in gray tones (up to 5 shades; further subjects are grouped as "Other"):

| Range | Bars |
|---|---|
| **Day** | last 14 days, one bar per day |
| **Week** | last 12 weeks (calendar weeks, locale first weekday), one bar per week |
| **Month** | last 12 months, one bar per month |

**Summary cards:**

- Today
- This week
- **Current streak**: consecutive days ending today with ≥ 5 min total. If today has < 5 min, the streak counts back from yesterday.
- Longest streak
- Sessions (count)
- Average session
- Longest session
- App attempts blocked (total)
- Tabs closed (total)
- Bails (count)

**Per-subject breakdown:** a horizontal bar list with total time per subject and its percentage, sorted descending. Subject detail shows the same cards filtered to that subject.

**Demo data:** Settings has a "Load demo data" button. It seeds about 30 days of sessions (`isDemo = true`) across existing subjects, creating "CS128" and "MATH241" if there are none. "Clear demo data" removes them.

## 11. UI

**Theme:**

- Monochrome black and white, following the system appearance. Primary = label color.
- Fonts: SF Pro. The timer uses SF Mono / `.monospacedDigit()`, weight `.ultraLight` to `.thin`.
- Spacing scale 4/8/16/24/40.
- No color accents. Destructive and attention states use weight and borders only.
- Buttons: the primary is a solid black fill (white in dark mode) with inverted text. The secondary is outlined with a 1 pt border.
- Corner radius 10.

**Screens:**

- **Main window** (`NavigationSplitView`):
  - **Sidebar:** "Subjects" list (name + total time), `+` button, then a divider, **Stats**, **Settings**. Empty state: "No subjects yet. Add one to lock in."
  - **SubjectDetailView:**
    - Big subject name.
    - Config summary: a layout preset thumbnail (small boxes diagram), sites, allowed apps as icons, extra domains.
    - **LOCK IN** button (full-width, 56 pt tall).
    - Edit button.
    - Subject stats (cards plus a 14-day mini bar chart).
- **SubjectEditorView** (sheet):
  - Name.
  - Preset picker: 4 visual thumbnails.
  - Site URL fields (count follows the preset).
  - Allowed apps: an `AppPickerView` listing `/Applications` and `/System/Applications` `.app` bundles with icon and name, plus search.
  - Extra domains (token field or list).
  - Validation: name non-empty, URLs parse.
- **LockInSheet:** mode choice. Open-ended, or 25 / 50 / 90 / custom minutes. Then a **LOCK IN** confirm.
- **LockedView** (main window during `thirds`/`mainSide`, or when the mini timer is clicked):
  - Subject name (small caps).
  - **Giant timer** filling the width (`HH:MM:SS`, scaled to fit), with a thin progress line in goal mode.
  - Counters: "3 apps blocked · 2 tabs closed".
  - **End** button (outlined).
- **MiniTimerPanel:** subject + timer (`MM:SS`, or `H:MM:SS`) + small ✕ (End). Clicking the body brings up the main window with LockedView.
- **GiveUpSheet:**
  - Shows the exact phrase and a text field. The **Bail** button is enabled only when the text matches.
  - Copy: "Ending early will be posted to Discord."
  - Cancel returns to the session.
- **ToastCenter:**
  - Top-right of the main screen, below the menu bar, 16 pt margin.
  - Width 320 pt. Black background with white text, inverted in dark mode.
  - Auto-dismiss after 3 s. Stacks up to 3.
  - Non-activating `NSPanel`, level `.statusBar`, `ignoresMouseEvents = true`.
- **StatsView:** range segmented control (Day/Week/Month), Swift Charts `BarMark` stacked by subject, summary cards grid, per-subject breakdown.
- **SettingsView:**
  - Display name.
  - Discord: enabled toggle, bot token (SecureField, saved to the Keychain), "Test connection" (shows the bot name and guild count), invite-URL help text.
  - Give-up phrase template.
  - Chrome automation status, with a "Request access" button that runs a harmless Chrome AppleScript to trigger the prompt.
  - Demo data load/clear.

## 12. Error handling

| Failure | Behavior |
|---|---|
| Chrome not installed | Lock in still proceeds without Chrome. Toast: "Google Chrome not found — sites not opened". Tab watch is disabled. |
| Automation denied (error −1743) | Toast: "Allow Chrome control in System Settings › Privacy & Security › Automation". The session continues without Chrome features. Settings shows the status. |
| Chrome profile not ready | Retry 3× at 1 s intervals, then show a toast and continue. |
| Invalid or empty site URL | Blocked in the editor by validation. At runtime, skip that window. |
| Discord disabled or no token | Skip silently. |
| Discord errors | One toast. Never blocks or crashes the session. |
| store.json corrupt or unreadable | Back it up as `store.corrupt-<timestamp>.json`, start empty, and show a toast. |
| No main screen | Use `NSScreen.screens.first`. If there is none, skip tiling. |

## 13. Testing

**Unit tests** (XCTest, `xcodebuild test`):

- **LayoutEngine:** each preset produces the right counts and zones that cover the width with no gaps or overlap. Rounding remainder goes to the last zone.
- **ScreenGeometry:** the Cocoa → Chrome bounds conversion.
- **DomainMatcher:** exact match, subdomain, `www.` stripping, a lookalike (`notyoutube.com` vs `youtube.com` → false), `chrome://newtab`, `about:blank`, garbage strings.
- **StatsEngine:**
  - Day, week and month buckets with fixed dates and a fixed calendar/time zone.
  - Streak, including today < 5 min and gaps.
  - Average and longest.
  - Bails count.
  - Interrupted sessions use the heartbeat.
- **DiscordMessages:** each template, duration formatting (0m, 59m, 1h 0m, 1h 20m), goal suffix.
- **ChannelPicker:** cached first, preferred names, position ordering, non-text channels excluded.
- **Store:** round-trip encode/decode, corrupt-file backup, interrupted-session finalization.

**Manual demo checklist** (run on the demo Mac before submitting): the success criteria in §1, steps 1–8, plus:

- Automation prompt flow on first use.
- Cmd+Q mid-session restores hidden apps.
- The Discord test button works.

## 14. Out of scope (YAGNI for tonight)

Multiple users or accounts, cloud sync, Discord OAuth/identity linking, Rich Presence, pre-launch blocking, a helper daemon, multi-monitor layouts, Spaces/full-screen handling, Safari/Arc support, per-subject schedules, reminders, signing/notarization, App Store, localization, and the old "Mirror" and "Ledger" GrokBot features.

## 15. Risks

| Risk | Mitigation |
|---|---|
| Chrome AppleScript timing on cold launch | Retry loop. Pre-launch Chrome before the demo. |
| The `NSAppleScript` tab poll stutters the main thread | Poll every 2 s with a single script call. Fall back to a background serial queue if needed. |
| A blocked app flashes before it hides | Accepted platform limit. Hide on both launch and activate. |
| Discord bot posts fail on a fresh bot (permissions or channel) | Test connection button. Rehearse with the real server before the demo. |
| Lock-in hides dev tools during development | It only hides (never quits). Add Xcode/Terminal to a test subject's allowed apps while developing. |
| Time | Build order puts the end-to-end lock-in path first and stats/polish last (see the implementation plan). |
