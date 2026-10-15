# Tofu

**Lock in on a subject, and your Mac turns into a study room.**

Tofu is a native macOS app. One click hides every other app and opens your study sites in Google Chrome, tiled in the layout you picked. Distractions are pushed away the moment they appear, your friends on Discord see that you're locked in, and the app tracks how long you actually stayed focused.

Built for **Code Ada 2026, Off the Clock** track.
 
## How a lock-in works

1. Create a subject, for example `CS128`. Give it one or two study sites, a window layout, and any extra apps it needs. The subject's name is what the AI judges tabs against.
2. Click **LOCK IN** and pick a mode:
   - open-ended, which counts up;
   - or a goal of 25, 50, 90 or a custom number of minutes, which counts down.
3. The app sets up the session:
   - It hides every other app, or asks them to quit if the setup says so.
   - It closes your existing browser windows and remembers their tabs. In Arc it also closes the unpinned tabs; pinned tabs stay.
   - It opens the setup's websites and apps, arranged in the chosen layout.
4. While you're locked in:
   - A disallowed app that launches or comes to the front is hidden right away. A toast appears top-right, and the attempt is counted.
   - Every 2 seconds, new Chrome tabs are checked by OpenAI ("is this page relevant to CS128?"). Off-task tabs are closed, with a toast. See Relevance check below.
   - A giant timer, or a small floating one, shows your time.
5. Ending a goal session early opens the Mirror: a short interrogation. The session stops only if you confirm a forfeit, and Discord hears about it. You can also take a timed break, which pauses blocking until the timer ends. With no API key, you type the give-up phrase instead (by default `I give up on CS128`).
6. When the session ends:
   - Everything that was hidden or quit comes back.
   - Your old browser windows open again with their tabs. So do the off-task tabs that were closed during the session. Pages that are already open are skipped.
   - The closed windows and tabs are saved to `closed-browser-tabs.json` next to `store.json`. If the app crashes, they reopen on the next launch.
   - The session shows up in your stats.

## Features

- **Subjects:** a name, a layout preset, one or two study sites and extra allowed apps.
- **Four layout presets** for the main display. See below.
- **App blocking:**
  - Chrome, Finder and Tofu are always allowed.
  - Every other app is hidden when it launches or activates.
  - An attempt counts at most once every 2 seconds per app.
- **AI relevance check for Chrome tabs:**
  - Every tab outside the subject's study sites is judged by the OpenAI Decisions API against the subject name.
  - An off-task tab is closed. A relevant tab stays open and is not checked again.
  - Study sites, blank new tabs, `chrome://` pages and tabs that were already open before the lock-in are never judged.
  - When there is no verdict, the app asks you. See Relevance check below.
- **Session modes:** open-ended, or a goal. A goal counts down and completes on its own. Ending it early opens the Mirror; a forfeit is posted as a bail.
- **Discord announcements** through your own bot. Lock-in, completion and bail messages go to one text channel per server.
- **Study companion:** an anime girl floats bottom-right while you're locked in. She greets you, chats idly, praises you at the halfway mark, and scolds you when an app or tab gets blocked. Personality in Settings: tsundere, yandere, or tsundere → yandere (she turns dark after 3 blocked attempts). Drop your own character art (e.g. Emilia) into `Application Support/Tofu/companion/` as `neutral.png`, `annoyed.png`, `pleased.png`, `dark.png` — the "Open images folder" button in Settings takes you there; without images a built-in portrait is drawn.
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

## Custom setups

Each zone of a setup is a **window**: either a website window or an app.

- **Website windows** open the first address, with any extra addresses as tabs behind it.
- **App windows** open an app, and optionally a folder or file in it. For example, Visual Studio Code on `~/code/cs128`.
- **Custom layout.** Pick the **Custom** tile and click **Capture current windows**. Every normal window on the main screen is copied with its position:
  - Chrome and Arc windows keep their open web pages.
  - Other apps keep the project folder of the file they show. This needs Accessibility.
  - You can edit or remove any captured window before saving.
- **Browser.** Choose Google Chrome or Arc per setup. Arc's pinned tabs are never listed or closed. Arc has no window bounds, so its windows are placed with Accessibility.
- **Other apps while locked in:**
  - **Hide them:** the default.
  - **Quit them:** apps are asked to quit normally, so they can ask to save. When the session ends they are opened again in the background. Finder, Terminal, iTerm, Xcode, Cursor, Activity Monitor and System Settings are only hidden.
- **Other desktops.** macOS has no public API to move windows to another desktop (Space), so "Quit them" is the stronger option.

## Requirements

- macOS 14 Sonoma or later.
- Xcode 16.3 or later.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) 2.46 or later: `brew install xcodegen`. The generated `.xcodeproj` is committed, so you only need XcodeGen after adding or removing source files.
- Google Chrome. Without it, a lock-in still hides and blocks apps, but no sites open and no tabs are watched.
- A Discord bot (optional). See Discord setup below.
- An OpenAI API key (optional) for the tab relevance check. Without one, you are asked about each site instead. See Relevance check above.

## Build and run

```bash
git clone https://github.com/zyin422/accountabilibrosis.git
cd accountabilibrosis/Tofu
xcodegen generate
open Tofu.xcodeproj    # then press ⌘R in Xcode
```

From the command line:

```bash
cd Tofu
xcodebuild -project Tofu.xcodeproj -scheme Tofu -configuration Release \
  -destination 'platform=macOS' -derivedDataPath build/DerivedData build
open build/DerivedData/Build/Products/Release/Tofu.app
```

> **While developing:** a lock-in hides Xcode and Terminal too. It never quits them. Add them to a test subject's allowed apps, or end the session from the mini timer.

## Updates

Tofu updates itself with [Sparkle](https://sparkle-project.org). Once a day it checks
`https://raw.githubusercontent.com/axion66/tofu-releases/main/appcast.xml`. When a newer version exists, a card appears
above **Stats** in the sidebar: **Update** opens Sparkle's window (release notes → Install → relaunch), **×** hides it;
it comes back at the next daily check after Tofu restarts. **Tofu → Check for Updates…** checks right away. Debug builds and builds from source never check.

**For friends (first install):**
1. Download the newest `Tofu-<version>.zip` from [axion66/tofu-releases](https://github.com/axion66/tofu-releases),
   unzip it and move `Tofu.app` to Applications.
2. The first launch is blocked because the app isn't notarized: open **System Settings → Privacy & Security** and click
   **Open Anyway**. Updates after that install without this step.
3. Release builds carry no keys. Paste the Discord bot token (ask the maintainer) and, optionally, your own OpenAI key
   in **Settings**. They live in your Keychain and survive updates.

**For the maintainer (publishing):**

```bash
cd Tofu
scripts/release.sh --dry-run              # build + sign + appcast locally, publishes nothing
scripts/release.sh 1.2 "What changed"     # bump, build, publish to axion66/tofu-releases, commit + tag (no source push)
```

The script refuses a dirty tree (untracked files count), a version that isn't newer than the current one, or an existing tag, and aborts if the build would ship `discord.env`.
It needs, on this Mac only:
- the **Accountabilibrosis Local Codesign** certificate — every release must be signed with it, or friends lose
  their Accessibility grant after updating;
- Sparkle's private EdDSA key in the login Keychain (created once with `generate_keys`; its public half is
  `SUPublicEDKey` in `project.yml`). Back it up:
  `build/ReleaseData/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys -x ~/tofu-sparkle-key.txt`
  and keep the file somewhere safe. Without it, friends' copies can't verify new updates and must be reinstalled.
- Also back up the **Accountabilibrosis Local Codesign** certificate with its private key (Keychain Access → export as
  .p12) and note its expiry date (self-signed certs default to 1 year). A different or expired certificate costs friends
  their Accessibility/Automation grants on the next update.

## Permissions

The main permission is **Automation → Google Chrome**.

- **What it's for:**
  - opening and arranging the study windows;
  - reading tab URLs and titles, and closing off-topic tabs;
  - minimizing and restoring your own windows.
- **When macOS asks:** once, with "Tofu wants access to control Google Chrome". To get the prompt out of the way early, use **Settings › Chrome › Request access**.

**Automation → Arc** is asked the same way the first time a setup uses Arc.

**Accessibility** is only needed to:

- place app windows and Arc windows;
- use custom layouts;
- capture each app's folder.

Grant it in **Settings › Window placement**. Chrome-only preset setups work without it. Rebuilds can make macOS forget the grant: remove the app from the Accessibility list and allow it again.

The app does **not** need Screen Recording, Full Disk Access or notification permission. It never scripts System Events.

- **Denied by accident?** Turn it back on in **System Settings › Privacy & Security › Automation › Tofu › Google Chrome**. A lock-in without it still hides and blocks apps.
- **Unsandboxed by design.** Hiding other apps does not work inside the App Sandbox, so the app can't ship on the Mac App Store. It is built locally and signed ad hoc (`CODE_SIGN_IDENTITY = -`).
- **Rebuilds can bring the prompt back.** An ad-hoc signature changes on every rebuild, so macOS may ask for Chrome access again. To reset the answer, run `tccutil reset AppleEvents com.tofu.app`.

## Daily priorities and the end-of-day recap

- **Morning screen.** A full-screen "Good morning" shows the first time you use the Mac each day, on launch, wake or unlock, after 4 AM and before the end-of-day time. Pick one of today's priorities, give it a setup if it has none, choose a length and **LOCK IN**. Open it any time with **Start my day** on the Today page; turn it off in **Settings › End of day**.
- **Today page** (top of the sidebar). Lists today's priorities. You can tick them off, add one (with the setup it belongs to), or start a lock-in on one.
- **After a lock-in.** The session summary asks "Did you finish …?" about the first open priority tied to that setup. This also happens if you end early. You can change the ticks later on the Today page or in the recap.
- **End of the day.** Starts from **End my day** on the Today page, or on its own at the time set in **Settings › End of day** (default 10 PM, once a day). If you're locked in, it waits until the session ends. A day runs from 4 AM to 4 AM, so wrapping up after midnight still counts for the evening before. It has three steps:
  1. confirm what you finished;
  2. say tomorrow's priorities out loud (or type them). gpt-4.1-mini splits them into a list and matches each to a setup. Without a key, the list is split locally.
  3. review the list and post one message to the group chat: the day's score, done, not done, and tomorrow's plan. The score is out of 100: 50 for the share of priorities finished, 30 for focus time (full marks at 90 minutes), and 20 for finishing the day without a bail.

## Relevance check (OpenAI)

The old website allowlist and blocklist are gone. While you're locked in, an AI decides which Chrome tabs belong.

- **What is asked.** For each new tab, the app sends the OpenAI Decisions API (`POST https://api.openai.com/v1/decisions`) one yes/no question: is this page off-task for the subject, for example `CS128`? The answer comes back as a probability. At 0.5 or higher the tab is closed, with a toast. Below that it stays.
- **What is not asked.**
  - Your study sites (and their subdomains) are never judged.
  - Blank tabs, `chrome://` pages and unparseable URLs are never judged.
  - Tabs that were already open before you locked in are never judged. Their windows are minimized and kept minimized. The exception is tabs on the always-closed list below: those are closed too.
- **Always closed, no AI needed.** Social media, email and messaging (Gmail, Outlook, WhatsApp Web, Discord and others), streaming, YouTube and shopping sites are closed as soon as they show up. The full list is in `Engine/DistractionList.swift`. A study site on one of those domains (for example a YouTube channel you added) is still kept, and so is a site you told the buddy you need. `aws.amazon.com` and `developer.amazon.com` are exempt.
- **Not sure? The buddy asks, out loud.** When the AI can't decide, a small popup appears bottom-right. It reads the question aloud with a built-in macOS voice, shows a countdown, and you answer by holding **Hold to talk**. Your speech is transcribed on this Mac and shown live. **Close it** closes the site right away. With no answer in 1 minute, the site is closed. Voice is only used for these new-tab questions.
- **Once per page.** Each URL is judged once per session. A tab that goes somewhere new is judged again. A URL that was judged off-task is closed straight away if it reappears.
- **The key.** It resolves like the Discord token:
  - A key saved in **Settings › Relevance check (OpenAI)** goes to the Keychain (service `com.tofu.openai`, account `api-key`) and wins.
  - Otherwise the team key from the repo-root `.env` is used. Add it next to the Discord token:

    ```
    OPENAI_API_KEY=<the team OpenAI key>
    ```

  - The build bundles `.env` into the app, so rebuild after editing it. Settings shows which key is in use: "Using your key from Keychain", "Using the team key from .env" or "No key — you'll be asked about each site".
- **Privacy.** While locked in, the URL and title of each checked tab (plus a page description, if one can be read) are sent to OpenAI. Nothing is sent when you're not locked in, and nothing is sent for the tabs listed above. Don't lock in with sensitive tabs open that you wouldn't want sent.
- **Fail-safe prompt.** If a check gives no verdict (no key, offline, timeout, an HTTP error or a refusal), the tab is not closed automatically. The app asks "Is `<host>` needed for `<subject>`?" with **Needed** and **Close tab**.
  - Only one question is on screen at a time, and each host is asked at most once per session.
  - **Needed** keeps every tab of that host for the rest of the session. **Close tab** closes every tab of that host, now and for the rest of the session.

## Discord setup

Discord bots can't join group DMs, so the app posts to one text channel in every server the bot is in.

### Team token (`.env`)

The team shares one bot. Its token lives in the repo-root `.env` file (this repo is private):

```
DISCORD_BOT_TOKEN=<the team bot token>
```

- **Bundled at build time.** Every build made from source copies `.env` into the app as `Resources/discord.env`. If the file is missing, the build still works and the app simply has no team token. Release builds made by `scripts/release.sh` bundle nothing: their keys come from Settings (Keychain).
- **Used automatically.** On a first launch (no saved data yet) with a token available, **Post lock-ins to Discord** starts out on.
- **Your own token wins.** A token saved in **Settings › Discord** goes to the Keychain and overrides the team token. **Remove** deletes it, and the team token applies again. Settings shows which one is in use: "Using your token from Keychain", "Using the team token from .env" or "No token".
- **Rebuild after editing `.env`.** The app only sees the copy made at build time.

To run your own bot instead of the team's, follow the steps below.

### Your own bot

1. Create an application at <https://discord.com/developers/applications> (**New Application**).
2. Open **Bot**, click **Reset Token**, and copy the token.
3. In Tofu, open **Settings › Discord**:
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
| Subjects, sessions, settings | `~/Library/Application Support/Tofu/store.json`. Writes are atomic. An unreadable file is renamed to `store.corrupt-<timestamp>.json`, and the app starts fresh. |
| Discord bot token (yours) | The Keychain: a generic password with service `com.tofu.discord` and account `bot-token`. It is never written to JSON or logs. It overrides the team token. |
| Discord bot token (team) | The repo's `.env`, copied into the app bundle as `Resources/discord.env` at build time (not in release builds from `scripts/release.sh`; those use Settings/Keychain). |
| OpenAI API key (yours) | The Keychain: a generic password with service `com.tofu.openai` and account `api-key`. It is never written to JSON or logs. It overrides the team key. |
| OpenAI API key (team) | The repo's `.env` (`OPENAI_API_KEY`), bundled into the app the same way as the Discord token (release builds bundle nothing). |
| Discord Application ID (only used for the invite link) | App preferences, key `discordAppID` |

To start over, quit the app and delete `~/Library/Application Support/Tofu/`. To remove your own token, use **Settings › Discord › Remove**. To remove your own OpenAI key, use **Settings › Relevance check (OpenAI) › Remove**.

## Known limitations

- **No pre-launch blocking.** macOS has no public API for it. The Screen Time APIs are not available on macOS, and Endpoint Security needs an entitlement from Apple. So a blocked app is hidden right after it launches or activates, and it can flash on screen for about 100–300 ms.
- **The app can't be sandboxed,** so it isn't on the App Store (see Permissions).
- **Discord bots can't join group DMs,** so messages go to server channels only.
- **Chrome profiles can't be chosen.** AppleScript can't open a window while Chrome is still loading a profile or showing the profile picker. The app retries 3 times, 1 second apart. Launch Chrome before a demo.
- **Quitting the app ends the lock-in.** Blocking runs inside the app, so ⌘Q is always an escape hatch.
  - On ⌘Q, the hidden apps come back and the session is saved as interrupted. Nothing is posted to Discord.
  - After a crash, the next launch closes the session at its last 30-second heartbeat. Hidden apps stay hidden until you open them.
- **Main display only.** Other displays, Spaces, full-screen apps and Stage Manager are not handled.
- **The AI can be wrong.** A tab is judged from its URL and title, so a borderline page may be kept or closed by mistake. Study sites are never judged, so put your main sites there.
- **Delay.** An off-topic tab can stay open for up to 2 seconds before it is checked, plus however long the OpenAI call takes.
- **Needs the network and a key.** Without a key or a connection every tab falls back to the "Is it needed?" question.
- **Midnight.** A session that crosses midnight counts toward the day it started.

## Project structure

```
accountabilibrosis/
├── README.md
├── .env                     team secrets (DISCORD_BOT_TOKEN, OPENAI_API_KEY), bundled into the app at build time
├── docs/superpowers/        design spec and implementation plan
├── *.pdf                    Code Ada 2026 packet and presentation guidelines
└── Tofu/
    ├── project.yml          XcodeGen spec (source of truth for the Xcode project)
    ├── Tofu.xcodeproj/
    ├── Tofu/
    │   ├── App/             app entry point, AppDelegate (⌘Q handling), AppModel (root state)
    │   ├── Models/          Subject, Session, AppSettings, StoreData
    │   ├── Persistence/     Store (JSON file), Keychain (bot token, OpenAI key), EnvFile (bundled team secrets)
    │   ├── Engine/          pure, unit-tested logic: LayoutEngine, DomainMatcher, TimeFormat, StatsEngine,
    │   │                    DemoData, SettingsStatus, StatsFormatting; SessionEngine (lock-in state machine)
    │   ├── System/          AppKit + AppleScript side effects: WorkspaceController, AppBlocker, BlockPolicy,
    │   │                    ChromeController, ChromeScripts, TabTriage (pure tab bookkeeping), RelevanceJudge
    │   │                    (OpenAI Decisions API), ScreenGeometry
    │   ├── Discord/         DiscordClient (REST), DiscordMessages, ChannelPicker, DiscordAnnouncer
    │   ├── UI/              SwiftUI screens and AppKit panels: sidebar, subject editor, lock-in sheet,
    │   │                    locked view, give-up sheet, mini timer, toasts, stats, settings, theme
    │   └── Resources/       Assets.xcassets (monochrome accent color)
    └── TofuTests/   XCTest suites for every pure unit, plus SessionEngine with fakes
```

Side effects sit behind small `@MainActor` protocols: `WorkspaceControlling`, `AppBlocking`, `ChromeControlling`, `RelevanceJudging`, `NeedPrompting`, `Toasting`, `Announcing` and `WindowPresenting`. So the whole lock-in lifecycle is tested without touching real apps, Chrome, OpenAI or Discord.

## Tests

```bash
cd Tofu && xcodegen generate && \
  xcodebuild -project Tofu.xcodeproj -scheme Tofu -destination 'platform=macOS' test 2>&1 | tail -30
```

The run ends with `** TEST SUCCEEDED **`. No test touches the network, Chrome, other apps or your real data:
- store tests write to a temporary folder;
- Keychain tests use their own service, `com.tofu.tests`.
