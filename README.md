# Accountabilibrosis

**Lock in on a subject, and your Mac turns into a study room.**

Accountabilibrosis is a native macOS app. One click hides every other app and opens your study sites in Google Chrome, tiled in the layout you picked. Distractions are pushed away the moment they appear, your friends on Discord see that you're locked in, and the app tracks how long you actually stayed focused.

Built for **Code Ada 2026, Off the Clock** track.

## How a lock-in works

1. Create a subject, for example `CS128`. Give it one or two study sites, a window layout, and any extra apps or domains it needs.
2. Click **LOCK IN** and pick a mode:
   - open-ended, which counts up;
   - or a goal of 25, 50, 90 or a custom number of minutes, which counts down.
3. The app sets up the session:
   - It hides every other app. It never quits them.
   - It minimizes your existing Chrome windows.
   - It opens the subject's sites in new Chrome windows, arranged in the chosen layout.
4. While you're locked in:
   - A disallowed app that launches or comes to the front is hidden right away. A toast appears top-right, and the attempt is counted.
   - Every 2 seconds, Chrome tabs outside the subject's domains are closed, with a toast.
   - A giant timer, or a small floating one, shows your time.
5. Ending a goal session early means typing the give-up phrase (by default `I give up on CS128`). Your Discord friends hear about it.
6. When the session ends:
   - Everything that was hidden comes back.
   - Your old Chrome windows are restored.
   - The session shows up in your stats.

## Features

- **Subjects:** a name, a layout preset, one or two study sites, extra allowed apps and extra allowed domains.
- **Four layout presets** for the main display. See below.
- **App blocking:**
  - Chrome, Finder and Accountabilibrosis are always allowed.
  - Every other app is hidden when it launches or activates.
  - An attempt counts at most once every 2 seconds per app.
- **Site blocking in Chrome:**
  - A tab is closed when its host isn't one of the subject's domains or a subdomain of one.
  - Blank new tabs and `chrome://` pages are left alone.
- **Session modes:** open-ended, or a goal. A goal counts down, completes on its own, and asks for a give-up phrase if you bail early.
- **Discord announcements** through your own bot. Lock-in, completion and bail messages go to one text channel per server.
- **Stats:**
  - Day, Week and Month bar charts, stacked by subject.
  - Today and this week.
  - Current and longest streak.
  - Session count, plus average and longest session.
  - Apps blocked, tabs closed and bails.
  - A per-subject breakdown.
  - Each subject page shows its own cards and a 14-day chart.
- **Demo data:** one click seeds about 30 days of sessions, so the charts look full.
- **Monochrome UI** that follows the system light/dark appearance.
- **Built-in toasts:** the app draws its own, so they need no notification permission and still show during Focus.

## Layout presets

```
Left / Right (2 sites)          Full (1 site)
+--------------+--------------+ +-----------------------------+
|              |              | |                             |
|   Chrome 1   |   Chrome 2   | |           Chrome            |
|              |              | |                             |
+--------------+--------------+ +-----------------------------+
  + floating mini timer           + floating mini timer

Thirds (2 sites)                70 / 30 (1 site)
+---------+---------+---------+ +--------------------+--------+
|  timer  |         |         | |                    | timer  |
|  (app)  | Chrome 1| Chrome 2| |       Chrome       | (app)  |
|         |         |         | |                    |        |
+---------+---------+---------+ +--------------------+--------+
```

- Every zone is full height, between the menu bar and the Dock, on the main display.
- In Thirds and 70 / 30, the app window holds the giant timer.
- In Left / Right and Full, a small timer floats at the top center of the screen.

## Requirements

- macOS 14 Sonoma or later.
- Xcode 16.3 or later.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) 2.46 or later: `brew install xcodegen`. The generated `.xcodeproj` is committed, so you only need XcodeGen after adding or removing source files.
- Google Chrome. Without it, a lock-in still hides and blocks apps, but no sites open and no tabs are watched.
- A Discord bot (optional). See Discord setup below.

## Build and run

```bash
git clone https://github.com/zyin422/accountabilibrosis.git
cd accountabilibrosis/Accountabilibrosis
xcodegen generate
open Accountabilibrosis.xcodeproj    # then press ⌘R in Xcode
```

From the command line:

```bash
cd Accountabilibrosis
xcodebuild -project Accountabilibrosis.xcodeproj -scheme Accountabilibrosis -configuration Release \
  -destination 'platform=macOS' -derivedDataPath build/DerivedData build
open build/DerivedData/Build/Products/Release/Accountabilibrosis.app
```

> **While developing:** a lock-in hides Xcode and Terminal too. It never quits them. Add them to a test subject's allowed apps, or end the session from the mini timer.

## Permissions

The app needs exactly one permission: **Automation → Google Chrome**.

- **What it's for:**
  - opening and arranging the study windows;
  - reading tab URLs and closing off-topic tabs;
  - minimizing and restoring your own windows.
- **When macOS asks:** once, with "Accountabilibrosis wants access to control Google Chrome". To get the prompt out of the way early, use **Settings › Chrome › Request access**.

The app does **not** need Accessibility, Screen Recording, Full Disk Access or notification permission. It never scripts System Events.

- **Denied by accident?** Turn it back on in **System Settings › Privacy & Security › Automation › Accountabilibrosis › Google Chrome**. A lock-in without it still hides and blocks apps.
- **Unsandboxed by design.** Hiding other apps does not work inside the App Sandbox, so the app can't ship on the Mac App Store. It is built locally and signed ad hoc (`CODE_SIGN_IDENTITY = -`).
- **Rebuilds can bring the prompt back.** An ad-hoc signature changes on every rebuild, so macOS may ask for Chrome access again. To reset the answer, run `tccutil reset AppleEvents com.accountabilibrosis.app`.

## Discord setup

Discord bots can't join group DMs, so the app posts to one text channel in every server the bot is in.

1. Create an application at <https://discord.com/developers/applications> (**New Application**).
2. Open **Bot**, click **Reset Token**, and copy the token.
3. In Accountabilibrosis, open **Settings › Discord**:
   1. Paste the token and click **Save**. It is stored in the Keychain.
   2. Turn on **Post lock-ins to Discord**.
4. Invite the bot to your server:
   1. Copy the **Application ID** from **General Information**.
   2. Paste it into **Settings › Discord setup › Application ID**.
   3. Click **Invite the bot to a server**. That opens the URL below, where 3072 = View Channel + Send Messages:

      `https://discord.com/oauth2/authorize?client_id=<APP_ID>&scope=bot&permissions=3072`
5. In your server, create a text channel named **#lock-in**. The bot picks its channel like this:
   - first `#lock-in`, `#locked-in`, `#lockin` and `#accountability`;
   - then any other text channel it can post in;
   - then it remembers the one that worked.
6. Click **Test connection**. It should show `Connected as <your bot> · 1 server`.

What your friends see (Discord renders the `**` as bold):

```
🔒 **Alex** is locked in on **CS128** (goal 50m)
✅ **Alex** locked in on **CS128** for **1h 20m** · tried other apps **3×** · closed **2** tabs
🏳️ **Alex** bailed on **CS128** after **12m** (goal 50m) · tried other apps **4×**
```

The name comes from **Settings › Profile › Display name**. Discord problems never block a session. If every server fails, you get one toast.

## Where your data lives

| Data | Location |
|---|---|
| Subjects, sessions, settings | `~/Library/Application Support/Accountabilibrosis/store.json`. Writes are atomic. An unreadable file is renamed to `store.corrupt-<timestamp>.json`, and the app starts fresh. |
| Discord bot token | The Keychain: a generic password with service `com.accountabilibrosis.discord` and account `bot-token`. It is never written to JSON or logs. |
| Discord Application ID (only used for the invite link) | App preferences, key `discordAppID` |

To start over, quit the app and delete `~/Library/Application Support/Accountabilibrosis/`. To remove the token, use **Settings › Discord › Remove**.

## Known limitations

- **No pre-launch blocking.** macOS has no public API for it. The Screen Time APIs are not available on macOS, and Endpoint Security needs an entitlement from Apple. So a blocked app is hidden right after it launches or activates, and it can flash on screen for about 100–300 ms.
- **The app can't be sandboxed,** so it isn't on the App Store (see Permissions).
- **Discord bots can't join group DMs,** so messages go to server channels only.
- **Chrome profiles can't be chosen.** AppleScript can't open a window while Chrome is still loading a profile or showing the profile picker. The app retries 3 times, 1 second apart. Launch Chrome before a demo.
- **Quitting the app ends the lock-in.** Blocking runs inside the app, so ⌘Q is always an escape hatch.
  - On ⌘Q, the hidden apps come back and the session is saved as interrupted. Nothing is posted to Discord.
  - After a crash, the next launch closes the session at its last 30-second heartbeat. Hidden apps stay hidden until you open them.
- **Main display only.** Other displays, Spaces, full-screen apps and Stage Manager are not handled.
- **Whole domains.** Allowing `youtube.com/watch?v=…` allows all of youtube.com.
- **Up to 2 seconds of delay.** An off-topic tab can stay open for up to 2 seconds before it is closed.
- **Midnight.** A session that crosses midnight counts toward the day it started.

## Project structure

```
accountabilibrosis/
├── README.md
├── docs/superpowers/        design spec and implementation plan
├── *.pdf                    Code Ada 2026 packet and presentation guidelines
└── Accountabilibrosis/
    ├── project.yml          XcodeGen spec (source of truth for the Xcode project)
    ├── Accountabilibrosis.xcodeproj/
    ├── Accountabilibrosis/
    │   ├── App/             app entry point, AppDelegate (⌘Q handling), AppModel (root state)
    │   ├── Models/          Subject, Session, AppSettings, StoreData
    │   ├── Persistence/     Store (JSON file), Keychain (bot token)
    │   ├── Engine/          pure, unit-tested logic: LayoutEngine, DomainMatcher, TimeFormat, StatsEngine,
    │   │                    DemoData, SettingsStatus, StatsFormatting; SessionEngine (lock-in state machine)
    │   ├── System/          AppKit + AppleScript side effects: WorkspaceController, AppBlocker, BlockPolicy,
    │   │                    ChromeController, ChromeScripts, ScreenGeometry
    │   ├── Discord/         DiscordClient (REST), DiscordMessages, ChannelPicker, DiscordAnnouncer
    │   ├── UI/              SwiftUI screens and AppKit panels: sidebar, subject editor, lock-in sheet,
    │   │                    locked view, give-up sheet, mini timer, toasts, stats, settings, theme
    │   └── Resources/       Assets.xcassets (monochrome accent color)
    └── AccountabilibrosisTests/   XCTest suites for every pure unit, plus SessionEngine with fakes
```

Side effects sit behind small `@MainActor` protocols: `WorkspaceControlling`, `AppBlocking`, `ChromeControlling`, `Toasting`, `Announcing` and `WindowPresenting`. So the whole lock-in lifecycle is tested without touching real apps, Chrome or Discord.

## Tests

```bash
cd Accountabilibrosis && xcodegen generate && \
  xcodebuild -project Accountabilibrosis.xcodeproj -scheme Accountabilibrosis -destination 'platform=macOS' test 2>&1 | tail -30
```

The run ends with `** TEST SUCCEEDED **`. No test touches the network, Chrome, other apps or your real data:
- store tests write to a temporary folder;
- Keychain tests use their own service, `com.accountabilibrosis.tests`.
