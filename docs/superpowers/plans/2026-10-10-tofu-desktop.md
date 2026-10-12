# Tofu macOS Lock-In App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS app. When the user locks in on a subject, it hides distractions, tiles Chrome study windows, blocks disallowed apps and sites, announces the session on Discord, and tracks lock-in time with a giant timer and statistics.

**Architecture:** A single SwiftUI app target with AppKit bridges, built with XcodeGen. Logic that can be tested without the OS lives in pure units: layout, domain matching, formatting, Discord channel picking, stats and demo data. Side effects sit behind `@MainActor` protocols (`WorkspaceControlling`, `AppBlocking`, `ChromeControlling`, `Toasting`, `Announcing`, `WindowPresenting`). That lets `SessionEngine`, the orchestrator, be unit-tested with fakes. Data is a single JSON file; the Discord bot token lives in the Keychain.

**Tech Stack:** Swift 6.1 toolchain in Swift 5 language mode, SwiftUI, AppKit, Swift Charts, Foundation `URLSession`, `NSAppleScript`, Security (Keychain), XCTest, and XcodeGen 2.46. No third-party packages.

**Spec:** `docs/superpowers/specs/2026-10-10-tofu-desktop-design.md`

## Global Constraints

- The project lives in the `Tofu/` folder at the repo root. It contains `project.yml`, the generated `Tofu.xcodeproj` (committed), the sources in `Tofu/` and the tests in `TofuTests/`.
- Deployment target is `macOS 14.0`. `SWIFT_VERSION` is `5.0`. Build with Xcode 16.3.
- Bundle ID is `com.tofu.app`. Set `ENABLE_APP_SANDBOX = NO`, `ENABLE_HARDENED_RUNTIME = NO` and `CODE_SIGN_IDENTITY = "-"` (ad-hoc).
- Set `INFOPLIST_KEY_NSAppleEventsUsageDescription` to: "Tofu opens and arranges your study sites in Google Chrome and closes off-topic tabs while you're locked in."
- No third-party dependencies.
- Never quit or force-quit other apps; only `hide()` them. Never script System Events. Do not require Accessibility permission.
- Store the Discord bot token only in the Keychain: service `com.tofu.discord`, account `bot-token`. Never put it in JSON, logs or source.
- The data file is `~/Library/Application Support/Tofu/store.json`.
- The UI is monochrome only: `Color.primary` and its opacities, plus system background. No accent colors. The timer uses a monospaced thin font (`Theme.timerFont`).
- Discord message texts must match spec §9 exactly. Formatting goes through `DiscordMessages` and `TimeFormat`.
- After adding or removing any Swift file, re-run `xcodegen generate` from `Tofu/`. `project.yml` includes source directories, not individual files.
- Standard test command, run from the repo root:
  `cd Tofu && xcodegen generate && xcodebuild -project Tofu.xcodeproj -scheme Tofu -destination 'platform=macOS' test 2>&1 | tail -30`
- Commands that begin with `cd Tofu` assume the shell starts at the repo root. Commit steps begin with `cd "$(git rev-parse --show-toplevel)"`, so they work from either folder; for any other "from the repo root" command, `cd` back to the repo root first.
- Every commit message ends with a blank line and then `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- The interface names and types in each task's **Interfaces** block are binding. Do not rename them.

## Review Focus

1. **Repeated attempts to open a hidden, disallowed app** (Dock click, Cmd-Tab, relaunch): the app is hidden every time. An attempt is counted at most once per 2 s per app. Chrome, Finder and our own app are never hidden. Covered by Task 7 (`BlockPolicy` and `AttemptDebouncer` tests).
2. **Site entries typed without a scheme, or with `www.`/uppercase** (e.g. `Piazza.com/class/x`): the site opens as `https://…` and its domain is allowed, including subdomains. Look-alike hosts (`notyoutube.com` against `youtube.com`) are not allowed. A blank new tab is never closed. Covered by Task 4 (`DomainMatcher` tests).
3. **App quit or crash mid-session:**
   - On Cmd+Q, hidden apps are unhidden, and the session is saved as `interrupted` with no Discord post.
   - After a crash, the next launch closes the open session at its last heartbeat.
   - Covered by Task 2 (`Store.finalizeInterrupted`/`load` tests) and Task 10 (`terminateNow` tests).
4. **Goal countdown reaching zero:** the session completes exactly once and posts exactly one ✅ message. After the goal, ending needs no give-up phrase. The give-up phrase match ignores case and surrounding whitespace. Covered by Task 10 (`tick`/`finish`/`phraseMatches` tests).
5. **Discord failures:**
   - A channel without permission (403) falls through to the next candidate. A 429 waits for `retry_after` once.
   - A guild whose candidates all fail is reported in `failedGuilds`.
   - A bad token never blocks or crashes a session.
   - Covered by Task 6 (`DiscordClient` tests with a mock transport) and Task 12 (`DiscordAnnouncer` tests).

---

### Task 1: Project scaffold

**Files:**
- Create: `Tofu/project.yml`
- Create: `Tofu/Tofu/Resources/Assets.xcassets/Contents.json`
- Create: `Tofu/Tofu/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json`
- Create: `Tofu/Tofu/Resources/Assets.xcassets/AccentColor.colorset/Contents.json`
- Create: `Tofu/Tofu/App/TofuApp.swift` (temporary; Task 13 replaces it)
- Create (generated by XcodeGen, committed): `Tofu/Tofu.xcodeproj/`
- Test: `Tofu/TofuTests/SmokeTests.swift`

**Interfaces:**
- Consumes: nothing. Requires XcodeGen 2.46 and Xcode 16.3.
- Produces:
  - Xcode project `Tofu/Tofu.xcodeproj` with:
    - app target `Tofu`: Swift module `Tofu`, bundle ID `com.tofu.app`, sources = every file under `Tofu/Tofu/`
    - hosted unit-test target `TofuTests`: `TEST_HOST` = the app, so `Bundle.main` is the app bundle; sources = every file under `Tofu/TofuTests/`
    - shared scheme `Tofu`, which builds the app and runs `TofuTests`
  - `@main struct TofuApp: App` (temporary; Task 13 replaces it)
  - Asset catalog with an empty `AppIcon` and an `AccentColor` that is black in light mode and white in dark mode, so system controls stay monochrome.

- [ ] **Step 1: Check the toolchain**

Run (from the repo root):

```bash
xcodegen --version && xcodebuild -version
```

Expected:

```
Version: 2.46.0
Xcode 16.3
Build version 16E140
```

If the output says `command not found: xcodegen`, install it with `brew install xcodegen` and run the command again.

- [ ] **Step 2: Create the XcodeGen spec**

Create `Tofu/project.yml`. Sources are whole directories, so new Swift files join their target after `xcodegen generate`. The test target is hosted by the app (`TEST_HOST`/`BUNDLE_LOADER`), and ad-hoc signing (`CODE_SIGN_IDENTITY: "-"`, `CODE_SIGN_STYLE: Manual`, empty `DEVELOPMENT_TEAM`) builds without an Apple ID. There is no entitlements file, so the app is unsandboxed.

```yaml
name: Tofu

options:
  bundleIdPrefix: com.tofu
  deploymentTarget:
    macOS: "14.0"
  createIntermediateGroups: true

settings:
  base:
    SWIFT_VERSION: "5.0"
    MACOSX_DEPLOYMENT_TARGET: "14.0"
    CODE_SIGN_IDENTITY: "-"
    CODE_SIGN_STYLE: Manual
    DEVELOPMENT_TEAM: ""
    ENABLE_APP_SANDBOX: NO
    ENABLE_HARDENED_RUNTIME: NO
    ENABLE_USER_SCRIPT_SANDBOXING: NO
    DEAD_CODE_STRIPPING: YES

targets:
  Tofu:
    type: application
    platform: macOS
    sources:
      - path: Tofu
    settings:
      base:
        PRODUCT_NAME: Tofu
        PRODUCT_BUNDLE_IDENTIFIER: com.tofu.app
        MARKETING_VERSION: "1.0"
        CURRENT_PROJECT_VERSION: "1"
        GENERATE_INFOPLIST_FILE: YES
        INFOPLIST_KEY_CFBundleDisplayName: Tofu
        INFOPLIST_KEY_LSApplicationCategoryType: public.app-category.productivity
        INFOPLIST_KEY_NSAppleEventsUsageDescription: "Tofu opens and arranges your study sites in Google Chrome and closes off-topic tabs while you're locked in."
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
        ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: AccentColor
        COMBINE_HIDPI_IMAGES: YES
        ENABLE_PREVIEWS: YES
        LD_RUNPATH_SEARCH_PATHS: "$(inherited) @executable_path/../Frameworks"

  TofuTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - path: TofuTests
    dependencies:
      - target: Tofu
    settings:
      base:
        PRODUCT_NAME: TofuTests
        PRODUCT_BUNDLE_IDENTIFIER: com.tofu.app.tests
        GENERATE_INFOPLIST_FILE: YES
        TEST_HOST: "$(BUILT_PRODUCTS_DIR)/Tofu.app/Contents/MacOS/Tofu"
        BUNDLE_LOADER: "$(TEST_HOST)"
        LD_RUNPATH_SEARCH_PATHS: "$(inherited) @executable_path/../Frameworks @loader_path/../Frameworks"

schemes:
  Tofu:
    build:
      targets:
        Tofu: all
        TofuTests: [test]
    run:
      config: Debug
    test:
      config: Debug
      gatherCoverageData: false
      targets:
        - name: TofuTests
          parallelizable: false
    profile:
      config: Release
    analyze:
      config: Debug
    archive:
      config: Release
```

- [ ] **Step 3: Create the asset catalog**

Create `Tofu/Tofu/Resources/Assets.xcassets/Contents.json`:

```json
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

Create `Tofu/Tofu/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json`. The slots stay empty; the build does not warn about it.

```json
{
  "images" : [
    { "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

Create `Tofu/Tofu/Resources/Assets.xcassets/AccentColor.colorset/Contents.json`. It is black in light mode and white in dark mode:

```json
{
  "colors" : [
    {
      "color" : {
        "color-space" : "srgb",
        "components" : { "alpha" : "1.000", "blue" : "0.000", "green" : "0.000", "red" : "0.000" }
      },
      "idiom" : "universal"
    },
    {
      "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ],
      "color" : {
        "color-space" : "srgb",
        "components" : { "alpha" : "1.000", "blue" : "1.000", "green" : "1.000", "red" : "1.000" }
      },
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

- [ ] **Step 4: Create the temporary app entry point**

Create `Tofu/Tofu/App/TofuApp.swift`:

```swift
import SwiftUI

/// Temporary app entry point. Task 13 replaces this file with the real app shell.
@main
struct TofuApp: App {
    var body: some Scene {
        WindowGroup {
            Text("Tofu")
                .font(.system(size: 34, weight: .semibold))
                .frame(minWidth: 480, minHeight: 320)
        }
    }
}
```

- [ ] **Step 5: Write the smoke test**

Create `Tofu/TofuTests/SmokeTests.swift`. It proves three things: the tests run inside the app bundle (`TEST_HOST` works), `@testable import` works, and the generated Info.plist carries the Automation usage string.

```swift
import XCTest
@testable import Tofu

final class SmokeTests: XCTestCase {
    func testTestsRunInsideTheAppBundle() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "com.tofu.app")
    }

    func testAppleEventsUsageDescriptionIsPresent() {
        let text = Bundle.main.object(forInfoDictionaryKey: "NSAppleEventsUsageDescription") as? String
        XCTAssertEqual(text, "Tofu opens and arranges your study sites in Google Chrome and closes off-topic tabs while you're locked in.")
    }
}
```

- [ ] **Step 6: Generate the project and run the smoke test**

Run (from the repo root):

```bash
cd Tofu && xcodegen generate && xcodebuild -project Tofu.xcodeproj -scheme Tofu -destination 'platform=macOS' test -only-testing:TofuTests/SmokeTests 2>&1 | tail -30
```

Expected: a `Created project at` line ending in `/Tofu/Tofu.xcodeproj`, then `Executed 2 tests, with 0 failures (0 unexpected)` and `** TEST SUCCEEDED **`.

The app launches briefly as the test host and may flash a window titled "Tofu". Some log lines are harmless and can be ignored:
- `[Connection] Unable to get synchronousRemoteObjectProxy` lines that mention `com.apple.linkd.autoShortcut`
- `xcodebuild: WARNING: Using the first of multiple matching destinations`

- [ ] **Step 7: Check the built Info.plist and signature**

Run (from the repo root):

```bash
cd Tofu && APP="$(xcodebuild -project Tofu.xcodeproj -scheme Tofu -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2; exit}')/Tofu.app" && plutil -p "$APP/Contents/Info.plist" | grep -E "CFBundleIdentifier|CFBundleDisplayName|LSApplicationCategoryType|NSAppleEventsUsageDescription|LSMinimumSystemVersion" && codesign -dv "$APP" 2>&1 | grep -E "^Signature"
```

Expected:

```
  "CFBundleDisplayName" => "Tofu"
  "CFBundleIdentifier" => "com.tofu.app"
  "LSApplicationCategoryType" => "public.app-category.productivity"
  "LSMinimumSystemVersion" => "14.0"
  "NSAppleEventsUsageDescription" => "Tofu opens and arranges your study sites in Google Chrome and closes off-topic tabs while you're locked in."
Signature=adhoc
```

- [ ] **Step 8: Commit**

Commit the generated `.xcodeproj` too. `xcuserdata/` is already in `.gitignore`.

```bash
cd "$(git rev-parse --show-toplevel)" && git add Tofu/project.yml Tofu/Tofu.xcodeproj Tofu/Tofu/App/TofuApp.swift Tofu/Tofu/Resources/Assets.xcassets Tofu/TofuTests/SmokeTests.swift && git commit -F - <<'EOF'
Scaffold Tofu macOS app with XcodeGen

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

Expected: `git status --short` prints nothing.

---

### Task 2: Models + Store + Keychain

**Files:**
- Create: `Tofu/Tofu/Models/Subject.swift`
- Create: `Tofu/Tofu/Models/Session.swift`
- Create: `Tofu/Tofu/Models/AppSettings.swift`
- Create: `Tofu/Tofu/Persistence/Store.swift`
- Create: `Tofu/Tofu/Persistence/Keychain.swift`
- Modify (regenerated): `Tofu/Tofu.xcodeproj/project.pbxproj`
- Test: `Tofu/TofuTests/ModelsTests.swift`
- Test: `Tofu/TofuTests/StoreTests.swift`
- Test: `Tofu/TofuTests/KeychainTests.swift`

**Interfaces:**
- Consumes: Task 1's project, targets and scheme. Foundation (`NSFullUserName`, `JSONEncoder`, `FileManager`) and Security (`SecItem*`).
- Produces (binding; later tasks use these exact names):
  - `enum LayoutPreset: String, Codable, CaseIterable, Identifiable { case split, full, thirds, mainSide; var id: String; var siteCount: Int; var appHasZone: Bool; var title: String }`
  - `struct AllowedApp: Codable, Hashable, Identifiable { var bundleID: String; var name: String; var id: String }`
  - `struct Subject: Codable, Identifiable, Hashable { var id: UUID; var name: String; var preset: LayoutPreset; var sites: [String]; var allowedApps: [AllowedApp]; var extraDomains: [String]; var createdAt: Date }` with `init(id: UUID = UUID(), name: String, preset: LayoutPreset = .split, sites: [String] = [], allowedApps: [AllowedApp] = [], extraDomains: [String] = [], createdAt: Date = Date())`
  - `enum SessionMode: Codable, Hashable { case open; case goal(minutes: Int); var goalMinutes: Int?; var goalSeconds: TimeInterval? }`
  - `enum SessionOutcome: String, Codable { case completed, bailed, interrupted }`
  - `struct Session: Codable, Identifiable, Hashable { var id: UUID; var subjectID: UUID; var subjectName: String; var mode: SessionMode; var start: Date; var end: Date?; var lastHeartbeat: Date; var blockedAttempts: Int; var closedTabs: Int; var outcome: SessionOutcome?; var isDemo: Bool; var duration: TimeInterval }` with `init(id: UUID = UUID(), subjectID: UUID, subjectName: String, mode: SessionMode, start: Date, end: Date? = nil, lastHeartbeat: Date? = nil, blockedAttempts: Int = 0, closedTabs: Int = 0, outcome: SessionOutcome? = nil, isDemo: Bool = false)`
  - `struct AppSettings: Codable, Equatable { var displayName: String; var discordEnabled: Bool; var giveUpTemplate: String; var channelCache: [String: String] }` with `init(displayName: String = NSFullUserName(), discordEnabled: Bool = false, giveUpTemplate: String = "I give up on {subject}", channelCache: [String: String] = [:])`
  - `struct StoreData: Codable, Equatable { var version: Int = 1; var subjects: [Subject] = []; var sessions: [Session] = []; var settings: AppSettings = AppSettings(); static var empty: StoreData }`
  - `struct StoreLoadResult { var data: StoreData; var warning: String? }`
  - `final class Store { let fileURL: URL; init(fileURL: URL); static func defaultURL() -> URL; func load() -> StoreLoadResult; func save(_ data: StoreData) throws; static func finalizeInterrupted(_ data: StoreData) -> StoreData }`
  - `enum Secrets { static let discordService = "com.tofu.discord"; static let discordAccount = "bot-token" }`
  - `enum Keychain { static func get(service: String, account: String) -> String?; @discardableResult static func set(_ value: String, service: String, account: String) -> Bool; static func delete(service: String, account: String) }`

- [ ] **Step 1: Write the failing model tests**

Create `Tofu/TofuTests/ModelsTests.swift`:

```swift
import XCTest
@testable import Tofu

final class ModelsTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_760_000_000)

    func testPresetSiteCountsAndAppZones() {
        XCTAssertEqual(LayoutPreset.split.siteCount, 2)
        XCTAssertEqual(LayoutPreset.full.siteCount, 1)
        XCTAssertEqual(LayoutPreset.thirds.siteCount, 2)
        XCTAssertEqual(LayoutPreset.mainSide.siteCount, 1)
        XCTAssertFalse(LayoutPreset.split.appHasZone)
        XCTAssertFalse(LayoutPreset.full.appHasZone)
        XCTAssertTrue(LayoutPreset.thirds.appHasZone)
        XCTAssertTrue(LayoutPreset.mainSide.appHasZone)
    }

    func testPresetTitlesAndOrder() {
        XCTAssertEqual(LayoutPreset.allCases, [.split, .full, .thirds, .mainSide])
        XCTAssertEqual(LayoutPreset.allCases.map(\.title), ["Left / Right", "Full", "Thirds", "70 / 30"])
        XCTAssertEqual(LayoutPreset.mainSide.id, "mainSide")
    }

    func testSessionModeGoalAccessors() {
        XCTAssertNil(SessionMode.open.goalMinutes)
        XCTAssertNil(SessionMode.open.goalSeconds)
        XCTAssertEqual(SessionMode.goal(minutes: 25).goalMinutes, 25)
        XCTAssertEqual(SessionMode.goal(minutes: 25).goalSeconds, 1500)
    }

    func testSessionModeCodableRoundTripBothCases() throws {
        for mode in [SessionMode.open, SessionMode.goal(minutes: 50)] {
            let data = try JSONEncoder().encode(mode)
            let decoded = try JSONDecoder().decode(SessionMode.self, from: data)
            XCTAssertEqual(decoded, mode)
        }
    }

    func testSessionDefaultsHeartbeatToStart() {
        let session = Session(subjectID: UUID(), subjectName: "CS128", mode: .open, start: t0)
        XCTAssertEqual(session.lastHeartbeat, t0)
        XCTAssertNil(session.end)
        XCTAssertNil(session.outcome)
        XCTAssertEqual(session.blockedAttempts, 0)
        XCTAssertEqual(session.closedTabs, 0)
        XCTAssertFalse(session.isDemo)
        XCTAssertEqual(session.duration, 0)
    }

    func testDurationUsesLastHeartbeatWhileActive() {
        let session = Session(subjectID: UUID(), subjectName: "CS128", mode: .open, start: t0,
                              lastHeartbeat: t0.addingTimeInterval(90))
        XCTAssertEqual(session.duration, 90)
    }

    func testDurationUsesEndWhenFinished() {
        let session = Session(subjectID: UUID(), subjectName: "CS128", mode: .goal(minutes: 25), start: t0,
                              end: t0.addingTimeInterval(1500), lastHeartbeat: t0.addingTimeInterval(1490),
                              outcome: .completed)
        XCTAssertEqual(session.duration, 1500)
    }

    func testDurationIsNeverNegative() {
        let session = Session(subjectID: UUID(), subjectName: "CS128", mode: .open, start: t0,
                              end: t0.addingTimeInterval(-30))
        XCTAssertEqual(session.duration, 0)
    }

    func testAppSettingsDefaults() {
        let settings = AppSettings(displayName: "Alex")
        XCTAssertEqual(settings.displayName, "Alex")
        XCTAssertFalse(settings.discordEnabled)
        XCTAssertEqual(settings.giveUpTemplate, "I give up on {subject}")
        XCTAssertEqual(settings.channelCache, [:])
    }

    func testEmptyStoreData() {
        let empty = StoreData.empty
        XCTAssertEqual(empty.version, 1)
        XCTAssertTrue(empty.subjects.isEmpty)
        XCTAssertTrue(empty.sessions.isEmpty)
    }

    func testSubjectDefaults() {
        let subject = Subject(name: "CS128")
        XCTAssertEqual(subject.preset, .split)
        XCTAssertEqual(subject.sites, [])
        XCTAssertEqual(subject.allowedApps, [])
        XCTAssertEqual(subject.extraDomains, [])
        XCTAssertEqual(AllowedApp(bundleID: "com.apple.Notes", name: "Notes").id, "com.apple.Notes")
    }
}
```

- [ ] **Step 2: Run the model tests and watch them fail**

Run (from the repo root):

```bash
cd Tofu && xcodegen generate && xcodebuild -project Tofu.xcodeproj -scheme Tofu -destination 'platform=macOS' test -only-testing:TofuTests/ModelsTests 2>&1 | tail -30
```

Expected: the test target fails to compile. The output lists errors such as `Cannot find 'Session' in scope`, `Cannot find 'AppSettings' in scope` and `Cannot find 'Subject' in scope` (the full log also has `error: cannot find 'LayoutPreset' in scope`), then `Testing cancelled because the build failed.` and `** TEST FAILED **`.

- [ ] **Step 3: Create `Subject.swift`**

Create `Tofu/Tofu/Models/Subject.swift`:

```swift
import Foundation

/// How the screen is split between Chrome study windows and our app while locked in.
enum LayoutPreset: String, Codable, CaseIterable, Identifiable {
    case split      // Chrome | Chrome (2 sites) + mini timer
    case full       // Chrome (1 site) + mini timer
    case thirds     // App | Chrome | Chrome (2 sites)
    case mainSide   // Chrome 70% | App 30% (1 site)

    var id: String { rawValue }
    var siteCount: Int { (self == .split || self == .thirds) ? 2 : 1 }
    var appHasZone: Bool { self == .thirds || self == .mainSide }
    var title: String {
        switch self {
        case .split: return "Left / Right"
        case .full: return "Full"
        case .thirds: return "Thirds"
        case .mainSide: return "70 / 30"
        }
    }
}

/// An app the user may keep using during a subject's session (in addition to the always-allowed set).
struct AllowedApp: Codable, Hashable, Identifiable {
    var bundleID: String
    var name: String
    var id: String { bundleID }
}

/// Something the user locks in on, e.g. "CS128", with its sites, layout and allowlists.
struct Subject: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var preset: LayoutPreset
    var sites: [String]
    var allowedApps: [AllowedApp]
    var extraDomains: [String]
    var createdAt: Date

    init(id: UUID = UUID(), name: String, preset: LayoutPreset = .split, sites: [String] = [],
         allowedApps: [AllowedApp] = [], extraDomains: [String] = [], createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.preset = preset
        self.sites = sites
        self.allowedApps = allowedApps
        self.extraDomains = extraDomains
        self.createdAt = createdAt
    }
}
```

- [ ] **Step 4: Create `Session.swift`**

Create `Tofu/Tofu/Models/Session.swift`:

```swift
import Foundation

/// Open-ended (count up) or goal (count down from `minutes`).
enum SessionMode: Codable, Hashable {
    case open
    case goal(minutes: Int)

    var goalMinutes: Int? {
        if case .goal(let minutes) = self { return minutes }
        return nil
    }
    var goalSeconds: TimeInterval? { goalMinutes.map { TimeInterval($0 * 60) } }
}

/// How a session ended. `interrupted` = our app quit or crashed mid-session.
enum SessionOutcome: String, Codable {
    case completed, bailed, interrupted
}

/// One lock-in. `end == nil` while it is active.
struct Session: Codable, Identifiable, Hashable {
    var id: UUID
    var subjectID: UUID
    var subjectName: String
    var mode: SessionMode
    var start: Date
    var end: Date?
    var lastHeartbeat: Date
    var blockedAttempts: Int
    var closedTabs: Int
    var outcome: SessionOutcome?
    var isDemo: Bool

    init(id: UUID = UUID(), subjectID: UUID, subjectName: String, mode: SessionMode, start: Date,
         end: Date? = nil, lastHeartbeat: Date? = nil, blockedAttempts: Int = 0, closedTabs: Int = 0,
         outcome: SessionOutcome? = nil, isDemo: Bool = false) {
        self.id = id
        self.subjectID = subjectID
        self.subjectName = subjectName
        self.mode = mode
        self.start = start
        self.end = end
        self.lastHeartbeat = lastHeartbeat ?? start
        self.blockedAttempts = blockedAttempts
        self.closedTabs = closedTabs
        self.outcome = outcome
        self.isDemo = isDemo
    }

    /// Seconds from start to end (or to the last heartbeat while active). Never negative.
    var duration: TimeInterval { max(0, (end ?? lastHeartbeat).timeIntervalSince(start)) }
}
```

- [ ] **Step 5: Create `AppSettings.swift`**

Create `Tofu/Tofu/Models/AppSettings.swift`. `StoreData` lives here as well:

```swift
import Foundation

/// User preferences persisted in store.json. The Discord bot token is NOT here (Keychain only).
struct AppSettings: Codable, Equatable {
    var displayName: String
    var discordEnabled: Bool
    var giveUpTemplate: String
    var channelCache: [String: String]   // guildID -> channelID that last succeeded

    init(displayName: String = NSFullUserName(), discordEnabled: Bool = false,
         giveUpTemplate: String = "I give up on {subject}", channelCache: [String: String] = [:]) {
        self.displayName = displayName
        self.discordEnabled = discordEnabled
        self.giveUpTemplate = giveUpTemplate
        self.channelCache = channelCache
    }
}

/// Everything stored in store.json.
struct StoreData: Codable, Equatable {
    var version: Int = 1
    var subjects: [Subject] = []
    var sessions: [Session] = []
    var settings: AppSettings = AppSettings()

    static var empty: StoreData { StoreData() }
}
```

- [ ] **Step 6: Run the model tests and watch them pass**

Run (from the repo root):

```bash
cd Tofu && xcodegen generate && xcodebuild -project Tofu.xcodeproj -scheme Tofu -destination 'platform=macOS' test -only-testing:TofuTests/ModelsTests 2>&1 | tail -30
```

Expected: `Executed 11 tests, with 0 failures (0 unexpected)` and `** TEST SUCCEEDED **`.

- [ ] **Step 7: Commit the models**

```bash
cd "$(git rev-parse --show-toplevel)" && git add Tofu/Tofu/Models Tofu/TofuTests/ModelsTests.swift Tofu/Tofu.xcodeproj && git commit -F - <<'EOF'
Add Subject, Session and AppSettings models

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

- [ ] **Step 8: Write the failing Store tests**

These tests cover Review Focus 3 (crash recovery): `testFinalizeInterruptedClosesOpenSessionsAtLastHeartbeat` and `testLoadAppliesFinalizeInterrupted`. Every test works in a fresh temp directory, so the real `store.json` is never touched. `testDefaultURLIsInApplicationSupport` only creates the `Tofu` folder in Application Support, which the app creates anyway.

The JSON uses `.iso8601` dates, which keep whole seconds only. That is why the tests use whole-second dates (`1_760_000_000` is `2025-10-09T08:53:20Z`).

Create `Tofu/TofuTests/StoreTests.swift`:

```swift
import XCTest
@testable import Tofu

final class StoreTests: XCTestCase {
    private var directory: URL!
    private var fileURL: URL!
    private let t0 = Date(timeIntervalSince1970: 1_760_000_000)   // whole seconds: ISO8601 keeps them exactly

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("store.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func sampleData() -> StoreData {
        let subjectID = UUID()
        let subject = Subject(id: subjectID, name: "CS128", preset: .thirds,
                              sites: ["https://cs128.org", "piazza.com/class/x"],
                              allowedApps: [AllowedApp(bundleID: "com.apple.Notes", name: "Notes")],
                              extraDomains: ["stackoverflow.com"], createdAt: t0)
        let finished = Session(subjectID: subjectID, subjectName: "CS128", mode: .goal(minutes: 25),
                               start: t0, end: t0.addingTimeInterval(1500),
                               lastHeartbeat: t0.addingTimeInterval(1490), blockedAttempts: 3, closedTabs: 2,
                               outcome: .completed)
        let open = Session(subjectID: subjectID, subjectName: "CS128", mode: .open,
                           start: t0.addingTimeInterval(3600), end: t0.addingTimeInterval(4200),
                           lastHeartbeat: t0.addingTimeInterval(4200), outcome: .bailed, isDemo: true)
        let settings = AppSettings(displayName: "Alex", discordEnabled: true,
                                   giveUpTemplate: "I quit {subject}", channelCache: ["111": "222"])
        return StoreData(version: 1, subjects: [subject], sessions: [finished, open], settings: settings)
    }

    private func backupFiles() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix("store.corrupt-") && $0.hasSuffix(".json") }
            .sorted()
    }

    func testMissingFileLoadsEmptyWithoutWarning() {
        let result = Store(fileURL: fileURL).load()
        XCTAssertEqual(result.data, StoreData.empty)
        XCTAssertNil(result.warning)
    }

    func testSaveThenLoadRoundTrips() throws {
        let store = Store(fileURL: fileURL)
        let data = sampleData()
        try store.save(data)
        let result = store.load()
        XCTAssertNil(result.warning)
        XCTAssertEqual(result.data, data)
    }

    func testSaveWritesPrettyPrintedJSONWithISODates() throws {
        try Store(fileURL: fileURL).save(sampleData())
        let text = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(text.contains("\"version\" : 1"), text)
        XCTAssertTrue(text.contains("\"2025-10-09T08:53:20Z\""), text)
        XCTAssertFalse(text.contains("bot-token"))
    }

    func testSaveCreatesMissingDirectory() throws {
        let nested = directory.appendingPathComponent("a/b/store.json")
        try Store(fileURL: nested).save(sampleData())
        XCTAssertTrue(FileManager.default.fileExists(atPath: nested.path))
    }

    func testCorruptFileIsBackedUpAndLoadsEmptyWithWarning() throws {
        try Data("not json {".utf8).write(to: fileURL)
        let result = Store(fileURL: fileURL).load()
        XCTAssertEqual(result.data, StoreData.empty)
        let warning = try XCTUnwrap(result.warning)
        XCTAssertTrue(warning.contains("store.corrupt-"), warning)
        let backups = try backupFiles()
        XCTAssertEqual(backups.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        let backupURL = directory.appendingPathComponent(backups[0])
        XCTAssertEqual(try String(contentsOf: backupURL, encoding: .utf8), "not json {")
    }

    func testSecondCorruptFileDoesNotOverwriteFirstBackup() throws {
        let store = Store(fileURL: fileURL)
        try Data("first".utf8).write(to: fileURL)
        _ = store.load()
        try Data("second".utf8).write(to: fileURL)
        _ = store.load()
        XCTAssertEqual(try backupFiles().count, 2)
    }

    func testFinalizeInterruptedClosesOpenSessionsAtLastHeartbeat() {
        var data = sampleData()
        let finished = data.sessions[0]
        let active = Session(subjectID: UUID(), subjectName: "MATH241", mode: .open, start: t0,
                             lastHeartbeat: t0.addingTimeInterval(600), blockedAttempts: 4)
        data.sessions.append(active)

        let result = Store.finalizeInterrupted(data)

        XCTAssertEqual(result.sessions[0], finished)
        XCTAssertEqual(result.sessions[1], data.sessions[1])
        let closed = result.sessions[2]
        XCTAssertEqual(closed.end, t0.addingTimeInterval(600))
        XCTAssertEqual(closed.outcome, .interrupted)
        XCTAssertEqual(closed.duration, 600)
        XCTAssertEqual(closed.blockedAttempts, 4)
        XCTAssertEqual(closed.id, active.id)
    }

    func testLoadAppliesFinalizeInterrupted() throws {
        var data = sampleData()
        data.sessions.append(Session(subjectID: UUID(), subjectName: "MATH241", mode: .goal(minutes: 50),
                                     start: t0, lastHeartbeat: t0.addingTimeInterval(1200)))
        let store = Store(fileURL: fileURL)
        try store.save(data)

        let loaded = store.load().data

        XCTAssertEqual(loaded.sessions.count, 3)
        XCTAssertEqual(loaded.sessions[2].end, t0.addingTimeInterval(1200))
        XCTAssertEqual(loaded.sessions[2].outcome, .interrupted)
        XCTAssertEqual(Array(loaded.sessions.prefix(2)), Array(data.sessions.prefix(2)))
    }

    func testDefaultURLIsInApplicationSupport() {
        let url = Store.defaultURL()
        XCTAssertTrue(url.path.hasSuffix("Library/Application Support/Tofu/store.json"), url.path)
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path,
                                                     isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }
}
```

- [ ] **Step 9: Run the Store tests and watch them fail**

Run (from the repo root):

```bash
cd Tofu && xcodegen generate && xcodebuild -project Tofu.xcodeproj -scheme Tofu -destination 'platform=macOS' test -only-testing:TofuTests/StoreTests 2>&1 | tail -30
```

Expected: the build fails with `error: cannot find 'Store' in scope` (in the summary it reads `Cannot find 'Store' in scope`), then `** TEST FAILED **`.

- [ ] **Step 10: Implement `Store`**

Create `Tofu/Tofu/Persistence/Store.swift`:
- A missing file is a normal first launch.
- A file that cannot be read or decoded is moved aside to `store.corrupt-<unix>.json`, with a `-2` or `-3` suffix if that name is taken. The app then starts empty with a warning, which `AppModel` (Task 12) shows as a toast.
- `load()` always closes sessions left open by a crash.

```swift
import Foundation

/// Result of `Store.load()`: the data to use, plus a user-facing warning when the file was unreadable.
struct StoreLoadResult {
    var data: StoreData
    var warning: String?
}

/// Reads and writes `StoreData` as one pretty-printed JSON file.
final class Store {
    let fileURL: URL

    init(fileURL: URL) { self.fileURL = fileURL }

    /// ~/Library/Application Support/Tofu/store.json (creates directory).
    static func defaultURL() -> URL {
        let fileManager = FileManager.default
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)
        let directory = base.appendingPathComponent("Tofu", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("store.json", isDirectory: false)
    }

    /// Missing file -> .empty, no warning. Corrupt -> rename to store.corrupt-<unix>.json, .empty, warning.
    /// Always applies finalizeInterrupted.
    func load() -> StoreLoadResult {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return StoreLoadResult(data: .empty, warning: nil)
        }
        do {
            let raw = try Data(contentsOf: fileURL)
            let decoded = try Self.makeDecoder().decode(StoreData.self, from: raw)
            return StoreLoadResult(data: Self.finalizeInterrupted(decoded), warning: nil)
        } catch {
            return StoreLoadResult(data: .empty, warning: backUpUnreadableFile())
        }
    }

    /// Atomic write, pretty-printed, ISO8601 dates.
    func save(_ data: StoreData) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoded = try Self.makeEncoder().encode(data)
        try encoded.write(to: fileURL, options: .atomic)
    }

    /// Sessions with end == nil get end = lastHeartbeat, outcome = .interrupted.
    static func finalizeInterrupted(_ data: StoreData) -> StoreData {
        var result = data
        for index in result.sessions.indices where result.sessions[index].end == nil {
            result.sessions[index].end = result.sessions[index].lastHeartbeat
            result.sessions[index].outcome = .interrupted
        }
        return result
    }

    // MARK: - Private

    /// Moves the unreadable file aside (never overwriting an earlier backup) and returns the warning text.
    private func backUpUnreadableFile() -> String {
        let fileManager = FileManager.default
        let directory = fileURL.deletingLastPathComponent()
        let baseName = fileURL.deletingPathExtension().lastPathComponent
        let stamp = Int(Date().timeIntervalSince1970)
        var backupURL = directory.appendingPathComponent("\(baseName).corrupt-\(stamp).json")
        var suffix = 2
        while fileManager.fileExists(atPath: backupURL.path) {
            backupURL = directory.appendingPathComponent("\(baseName).corrupt-\(stamp)-\(suffix).json")
            suffix += 1
        }
        do {
            try fileManager.moveItem(at: fileURL, to: backupURL)
            return "Saved data couldn't be read. It was backed up as \(backupURL.lastPathComponent) and the app started fresh."
        } catch {
            return "Saved data couldn't be read and couldn't be backed up. The app started fresh."
        }
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
```

- [ ] **Step 11: Run the Store tests and watch them pass**

Run (from the repo root):

```bash
cd Tofu && xcodegen generate && xcodebuild -project Tofu.xcodeproj -scheme Tofu -destination 'platform=macOS' test -only-testing:TofuTests/StoreTests 2>&1 | tail -30
```

Expected: `Executed 9 tests, with 0 failures (0 unexpected)` and `** TEST SUCCEEDED **`.

- [ ] **Step 12: Commit the Store**

```bash
cd "$(git rev-parse --show-toplevel)" && git add Tofu/Tofu/Persistence/Store.swift Tofu/TofuTests/StoreTests.swift Tofu/Tofu.xcodeproj && git commit -F - <<'EOF'
Add JSON Store with corrupt-file backup and crash recovery

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

- [ ] **Step 13: Write the failing Keychain tests**

The tests use the dedicated service `com.tofu.tests` and a fresh account name per test, then delete the item in `tearDown`. The real `com.tofu.discord` item is never touched. Each test reads only items created by the same build, so macOS shows no keychain password dialog.

Create `Tofu/TofuTests/KeychainTests.swift`:

```swift
import XCTest
@testable import Tofu

/// Uses a dedicated test service so the real Discord token is never touched.
final class KeychainTests: XCTestCase {
    private let service = "com.tofu.tests"
    private var account = ""

    override func setUp() {
        super.setUp()
        account = "test-\(UUID().uuidString)"
    }

    override func tearDown() {
        Keychain.delete(service: service, account: account)
        super.tearDown()
    }

    func testSecretsCoordinates() {
        XCTAssertEqual(Secrets.discordService, "com.tofu.discord")
        XCTAssertEqual(Secrets.discordAccount, "bot-token")
    }

    func testMissingItemReturnsNil() {
        XCTAssertNil(Keychain.get(service: service, account: account))
    }

    func testSetThenGet() {
        XCTAssertTrue(Keychain.set("token-1", service: service, account: account))
        XCTAssertEqual(Keychain.get(service: service, account: account), "token-1")
    }

    func testSetOverwritesExistingValue() {
        XCTAssertTrue(Keychain.set("token-1", service: service, account: account))
        XCTAssertTrue(Keychain.set("token-2", service: service, account: account))
        XCTAssertEqual(Keychain.get(service: service, account: account), "token-2")
    }

    func testDeleteRemovesItemAndIsSafeWhenMissing() {
        Keychain.set("token-1", service: service, account: account)
        Keychain.delete(service: service, account: account)
        XCTAssertNil(Keychain.get(service: service, account: account))
        Keychain.delete(service: service, account: account)
        XCTAssertNil(Keychain.get(service: service, account: account))
    }
}
```

- [ ] **Step 14: Run the Keychain tests and watch them fail**

Run (from the repo root):

```bash
cd Tofu && xcodegen generate && xcodebuild -project Tofu.xcodeproj -scheme Tofu -destination 'platform=macOS' test -only-testing:TofuTests/KeychainTests 2>&1 | tail -30
```

Expected: the build fails with `error: cannot find 'Keychain' in scope` and `error: cannot find 'Secrets' in scope`, then `** TEST FAILED **`.

- [ ] **Step 15: Implement `Keychain`**

Create `Tofu/Tofu/Persistence/Keychain.swift`. It stores a generic password in the login keychain. It does not use `kSecUseDataProtectionKeychain`, because that keychain needs a keychain-access-group entitlement, which an ad-hoc signed app does not have (it fails with `-34018`).

After each rebuild the ad-hoc signature changes. The first time a new build reads the token saved by an older build, macOS may ask "Tofu wants to use your confidential information stored in 'com.tofu.discord'". Click **Always Allow**.

```swift
import Foundation
import Security

/// Keychain coordinates for secrets. The Discord bot token lives only here, never in store.json.
enum Secrets {
    static let discordService = "com.tofu.discord"
    static let discordAccount = "bot-token"
}

/// Minimal generic-password wrapper around the login keychain.
enum Keychain {
    /// The stored UTF-8 string, or nil when missing or unreadable.
    static func get(service: String, account: String) -> String? {
        var query = baseQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Creates or overwrites the item. Returns false if the keychain rejected the write.
    @discardableResult static func set(_ value: String, service: String, account: String) -> Bool {
        let query = baseQuery(service: service, account: account)
        let data = Data(value.utf8)
        let updateStatus = SecItemUpdate(query as CFDictionary,
                                         [kSecValueData as String: data] as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        guard updateStatus == errSecItemNotFound else { return false }
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrLabel as String] = service
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    /// Removes the item if present. Missing items are not an error.
    static func delete(service: String, account: String) {
        SecItemDelete(baseQuery(service: service, account: account) as CFDictionary)
    }

    private static func baseQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
```

- [ ] **Step 16: Run the Keychain tests and watch them pass**

Run (from the repo root):

```bash
cd Tofu && xcodegen generate && xcodebuild -project Tofu.xcodeproj -scheme Tofu -destination 'platform=macOS' test -only-testing:TofuTests/KeychainTests 2>&1 | tail -30
```

Expected: `Executed 5 tests, with 0 failures (0 unexpected)` and `** TEST SUCCEEDED **`.

- [ ] **Step 17: Run the full suite and commit**

Run (from the repo root):

```bash
cd Tofu && xcodegen generate && xcodebuild -project Tofu.xcodeproj -scheme Tofu -destination 'platform=macOS' test 2>&1 | tail -30
```

Expected: `Executed 27 tests, with 0 failures (0 unexpected)` and `** TEST SUCCEEDED **`. The 27 tests are SmokeTests 2, ModelsTests 11, StoreTests 9 and KeychainTests 5.

```bash
cd "$(git rev-parse --show-toplevel)" && git add Tofu/Tofu/Persistence/Keychain.swift Tofu/TofuTests/KeychainTests.swift Tofu/Tofu.xcodeproj && git commit -F - <<'EOF'
Add Keychain wrapper for the Discord bot token

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

Expected: `git status --short` prints nothing.

### Task 3: LayoutEngine + ScreenGeometry

Pure window math for spec §7. `LayoutEngine` splits the main screen's visible frame (Cocoa coordinates, bottom-left origin) into full-height zones for a preset. `ScreenGeometry` converts those Cocoa rects into Chrome AppleScript `bounds` (top-left origin of the primary screen, y going down). It also wraps the two `NSScreen` lookups that `AppModel` (Task 12) injects into `SessionEngine` (Task 10).

Zone widths use integer weights (1:1, 1:1:1, 7:3) instead of `0.7`/`0.3`, so the arithmetic is exact. Every zone except the last is rounded **down** to whole points. The last zone takes `visible.width − used`, so the zones always cover the width exactly.

**Files:**
- Create: `Tofu/Tofu/Engine/LayoutEngine.swift`
- Create: `Tofu/Tofu/System/ScreenGeometry.swift`
- Test: `Tofu/TofuTests/LayoutEngineTests.swift`
- Test: `Tofu/TofuTests/ScreenGeometryTests.swift`
- Modify (regenerated by `xcodegen generate`): `Tofu/Tofu.xcodeproj`

**Interfaces:**
- Consumes (Task 2, `Models/Subject.swift`):
  ```swift
  enum LayoutPreset: String, Codable, CaseIterable, Identifiable {
      case split, full, thirds, mainSide
      var siteCount: Int { get }    // split/thirds: 2, full/mainSide: 1
      var appHasZone: Bool { get }  // thirds/mainSide
  }
  ```
- Produces:
  ```swift
  struct LayoutResult: Equatable {
      var chromeFrames: [CGRect]   // left -> right, count == preset.siteCount
      var appFrame: CGRect?        // non-nil iff preset.appHasZone
  }
  enum LayoutEngine {
      static func layout(_ preset: LayoutPreset, in visible: CGRect) -> LayoutResult
  }
  struct ChromeBounds: Equatable {
      var left: Int
      var top: Int
      var right: Int
      var bottom: Int
  }
  enum ScreenGeometry {
      static func chromeBounds(for rect: CGRect, primaryHeight: CGFloat) -> ChromeBounds
      @MainActor static func mainVisibleFrame() -> CGRect?   // (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
      @MainActor static func primaryHeight() -> CGFloat      // NSScreen.screens.first?.frame.height ?? 0
  }
  ```

- [ ] **Step 1: Write the failing LayoutEngine tests**

Create `Tofu/TofuTests/LayoutEngineTests.swift`:

```swift
import XCTest
@testable import Tofu

final class LayoutEngineTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)

    func testEveryPresetHasOneChromeFramePerSiteAndAnAppFrameOnlyWhenItHasAZone() {
        for preset in LayoutPreset.allCases {
            let result = LayoutEngine.layout(preset, in: screen)
            XCTAssertEqual(result.chromeFrames.count, preset.siteCount, "\(preset)")
            XCTAssertEqual(result.appFrame != nil, preset.appHasZone, "\(preset)")
        }
    }

    func testPresetCountsAndAppFrameNilness() {
        let split = LayoutEngine.layout(.split, in: screen)
        XCTAssertEqual(split.chromeFrames.count, 2)
        XCTAssertNil(split.appFrame)

        let full = LayoutEngine.layout(.full, in: screen)
        XCTAssertEqual(full.chromeFrames.count, 1)
        XCTAssertNil(full.appFrame)

        let thirds = LayoutEngine.layout(.thirds, in: screen)
        XCTAssertEqual(thirds.chromeFrames.count, 2)
        XCTAssertNotNil(thirds.appFrame)

        let mainSide = LayoutEngine.layout(.mainSide, in: screen)
        XCTAssertEqual(mainSide.chromeFrames.count, 1)
        XCTAssertNotNil(mainSide.appFrame)
    }

    func testSplitMakesTwoEqualHalves() {
        XCTAssertEqual(LayoutEngine.layout(.split, in: screen), LayoutResult(chromeFrames: [
            CGRect(x: 0, y: 0, width: 500, height: 800),
            CGRect(x: 500, y: 0, width: 500, height: 800),
        ], appFrame: nil))
    }

    func testFullUsesTheWholeVisibleArea() {
        XCTAssertEqual(LayoutEngine.layout(.full, in: screen),
                       LayoutResult(chromeFrames: [screen], appFrame: nil))
    }

    func testThirdsPutsAppFirstAndLastZoneAbsorbsRemainder() {
        let result = LayoutEngine.layout(.thirds, in: screen)
        XCTAssertEqual(result.appFrame, CGRect(x: 0, y: 0, width: 333, height: 800))
        XCTAssertEqual(result.chromeFrames, [
            CGRect(x: 333, y: 0, width: 333, height: 800),
            CGRect(x: 666, y: 0, width: 334, height: 800),
        ])
    }

    func testMainSideIsSeventyThirtyWithChromeOnTheLeft() {
        let result = LayoutEngine.layout(.mainSide, in: screen)
        XCTAssertEqual(result.chromeFrames, [CGRect(x: 0, y: 0, width: 700, height: 800)])
        XCTAssertEqual(result.appFrame, CGRect(x: 700, y: 0, width: 300, height: 800))
    }

    func testOddWidthRemainderGoesToTheLastZone() {
        let visible = CGRect(x: 0, y: 0, width: 1001, height: 800)
        XCTAssertEqual(LayoutEngine.layout(.split, in: visible).chromeFrames.map(\.width), [500, 501])
        let thirds = LayoutEngine.layout(.thirds, in: visible)
        XCTAssertEqual(thirds.appFrame?.width, 333)
        XCTAssertEqual(thirds.chromeFrames.map(\.width), [333, 335])
        let mainSide = LayoutEngine.layout(.mainSide, in: visible)
        XCTAssertEqual(mainSide.chromeFrames.map(\.width), [700])
        XCTAssertEqual(mainSide.appFrame?.width, 301)
    }

    func testNonZeroOriginAndFullHeightArePreserved() {
        let visible = CGRect(x: 100, y: 50, width: 1000, height: 700)

        XCTAssertEqual(LayoutEngine.layout(.split, in: visible).chromeFrames, [
            CGRect(x: 100, y: 50, width: 500, height: 700),
            CGRect(x: 600, y: 50, width: 500, height: 700),
        ])

        let thirds = LayoutEngine.layout(.thirds, in: visible)
        XCTAssertEqual(thirds.appFrame, CGRect(x: 100, y: 50, width: 333, height: 700))
        XCTAssertEqual(thirds.chromeFrames, [
            CGRect(x: 433, y: 50, width: 333, height: 700),
            CGRect(x: 766, y: 50, width: 334, height: 700),
        ])

        let mainSide = LayoutEngine.layout(.mainSide, in: visible)
        XCTAssertEqual(mainSide.chromeFrames, [CGRect(x: 100, y: 50, width: 700, height: 700)])
        XCTAssertEqual(mainSide.appFrame, CGRect(x: 800, y: 50, width: 300, height: 700))

        for preset in LayoutPreset.allCases {
            let result = LayoutEngine.layout(preset, in: visible)
            for zone in result.chromeFrames + [result.appFrame].compactMap({ $0 }) {
                XCTAssertEqual(zone.minY, 50, "\(preset)")
                XCTAssertEqual(zone.height, 700, "\(preset)")
            }
        }
    }

    func testZonesCoverTheWidthExactlyWithNoGapsOrOverlap() {
        for width in [CGFloat(1000), 1001, 1512, 1728] {
            let visible = CGRect(x: 0, y: 25, width: width, height: 900)
            for preset in LayoutPreset.allCases {
                let label = "\(preset) @ \(width)"
                let result = LayoutEngine.layout(preset, in: visible)
                let zones = (result.chromeFrames + [result.appFrame].compactMap({ $0 }))
                    .sorted { $0.minX < $1.minX }
                XCTAssertEqual(zones.first?.minX, visible.minX, label)
                XCTAssertEqual(zones.last?.maxX, visible.maxX, label)
                for (left, right) in zip(zones, zones.dropFirst()) {
                    XCTAssertEqual(left.maxX, right.minX, label)
                }
                XCTAssertEqual(zones.reduce(CGFloat(0)) { $0 + $1.width }, width, label)
                for zone in zones {
                    XCTAssertEqual(zone.width, zone.width.rounded(.down), "whole points: \(label)")
                    XCTAssertEqual(zone.minY, visible.minY, label)
                    XCTAssertEqual(zone.height, visible.height, label)
                }
            }
        }
    }
}
```

- [ ] **Step 2: Run the LayoutEngine tests and confirm they fail**

Run from the repo root:

```bash
cd Tofu && xcodegen generate && xcodebuild -project Tofu.xcodeproj -scheme Tofu -destination 'platform=macOS' test -only-testing:TofuTests/LayoutEngineTests 2>&1 | tail -30
```

Expected: the test target does not compile. The log contains `error: cannot find 'LayoutEngine' in scope` and `error: cannot find 'LayoutResult' in scope`; the `Testing failed:` summary lists `Cannot find 'LayoutEngine' in scope`. The last line is `** TEST FAILED **`.

- [ ] **Step 3: Implement LayoutEngine**

Create `Tofu/Tofu/Engine/LayoutEngine.swift`:

```swift
import CoreGraphics

/// Window frames for one layout preset, in Cocoa coordinates (bottom-left origin).
struct LayoutResult: Equatable {
    /// Chrome window frames, left to right. Count equals `preset.siteCount`.
    var chromeFrames: [CGRect]
    /// Frame for our own window. Non-nil exactly when `preset.appHasZone`.
    var appFrame: CGRect?
}

/// Splits the visible screen area into full-height zones for a layout preset (spec §7).
enum LayoutEngine {
    /// What occupies one zone.
    private enum ZoneKind {
        case chrome
        case app
    }

    /// One zone and its share of the width as an integer weight.
    private struct Zone {
        let kind: ZoneKind
        let weight: Int
    }

    /// Zones left to right. Integer weights keep the arithmetic exact (no 0.7 float drift).
    private static func zones(for preset: LayoutPreset) -> [Zone] {
        switch preset {
        case .split:
            return [Zone(kind: .chrome, weight: 1), Zone(kind: .chrome, weight: 1)]
        case .full:
            return [Zone(kind: .chrome, weight: 1)]
        case .thirds:
            return [Zone(kind: .app, weight: 1), Zone(kind: .chrome, weight: 1), Zone(kind: .chrome, weight: 1)]
        case .mainSide:
            return [Zone(kind: .chrome, weight: 7), Zone(kind: .app, weight: 3)]
        }
    }

    /// `visible` is Cocoa coordinates (bottom-left origin). Zones are full-height, left->right,
    /// widths rounded down to whole points; the last zone absorbs the remainder.
    static func layout(_ preset: LayoutPreset, in visible: CGRect) -> LayoutResult {
        let plan = zones(for: preset)
        let totalWeight = CGFloat(plan.reduce(0) { $0 + $1.weight })
        var result = LayoutResult(chromeFrames: [], appFrame: nil)
        var used: CGFloat = 0
        for (index, zone) in plan.enumerated() {
            let isLast = index == plan.count - 1
            let width = isLast
                ? visible.width - used
                : (visible.width * CGFloat(zone.weight) / totalWeight).rounded(.down)
            let frame = CGRect(x: visible.minX + used, y: visible.minY, width: width, height: visible.height)
            switch zone.kind {
            case .chrome:
                result.chromeFrames.append(frame)
            case .app:
                result.appFrame = frame
            }
            used += width
        }
        return result
    }
}
```

- [ ] **Step 4: Run the LayoutEngine tests and confirm they pass**

Run from the repo root:

```bash
cd Tofu && xcodegen generate && xcodebuild -project Tofu.xcodeproj -scheme Tofu -destination 'platform=macOS' test -only-testing:TofuTests/LayoutEngineTests 2>&1 | tail -30
```

Expected: `Test Suite 'LayoutEngineTests' passed`, `Executed 9 tests, with 0 failures (0 unexpected)`, and the last line `** TEST SUCCEEDED **`.

- [ ] **Step 5: Write the failing ScreenGeometry tests**

Create `Tofu/TofuTests/ScreenGeometryTests.swift`:

```swift
import AppKit
import XCTest
@testable import Tofu

final class ScreenGeometryTests: XCTestCase {
    func testFlipsTheYAxisAgainstThePrimaryScreenHeight() {
        let bounds = ScreenGeometry.chromeBounds(for: CGRect(x: 0, y: 0, width: 840, height: 1020),
                                                 primaryHeight: 1050)
        XCTAssertEqual(bounds, ChromeBounds(left: 0, top: 30, right: 840, bottom: 1050))
    }

    func testNonZeroOrigin() {
        let bounds = ScreenGeometry.chromeBounds(for: CGRect(x: 100, y: 50, width: 600, height: 900),
                                                 primaryHeight: 1050)
        XCTAssertEqual(bounds, ChromeBounds(left: 100, top: 100, right: 700, bottom: 1000))
    }

    func testRoundsToTheNearestWholePoint() {
        let bounds = ScreenGeometry.chromeBounds(for: CGRect(x: 0.4, y: 10.6, width: 333.3, height: 500.2),
                                                 primaryHeight: 1000)
        XCTAssertEqual(bounds, ChromeBounds(left: 0, top: 489, right: 334, bottom: 989))
    }

    func testScreenAboveThePrimaryGetsNegativeTop() {
        let bounds = ScreenGeometry.chromeBounds(for: CGRect(x: 0, y: 1050, width: 1920, height: 1080),
                                                 primaryHeight: 1050)
        XCTAssertEqual(bounds, ChromeBounds(left: 0, top: -1080, right: 1920, bottom: 0))
    }

    func testNonFiniteInputDoesNotTrap() {
        let bounds = ScreenGeometry.chromeBounds(for: .null, primaryHeight: .nan)
        XCTAssertEqual(bounds, ChromeBounds(left: 0, top: 0, right: 0, bottom: 0))
    }

    func testSplitLayoutConvertsToChromeBounds() {
        // 1440x900 primary screen, 25 pt menu bar, Dock hidden: visible frame is 1440x875 at the origin.
        let layout = LayoutEngine.layout(.split, in: CGRect(x: 0, y: 0, width: 1440, height: 875))
        let bounds = layout.chromeFrames.map { ScreenGeometry.chromeBounds(for: $0, primaryHeight: 900) }
        XCTAssertEqual(bounds, [
            ChromeBounds(left: 0, top: 25, right: 720, bottom: 900),
            ChromeBounds(left: 720, top: 25, right: 1440, bottom: 900),
        ])
    }

    @MainActor func testLiveScreenQueriesAgreeWithNSScreen() {
        if NSScreen.screens.isEmpty {
            XCTAssertNil(ScreenGeometry.mainVisibleFrame())
            XCTAssertEqual(ScreenGeometry.primaryHeight(), 0)
        } else {
            XCTAssertEqual(ScreenGeometry.primaryHeight(), NSScreen.screens.first?.frame.height)
            let visible = ScreenGeometry.mainVisibleFrame()
            XCTAssertNotNil(visible)
            XCTAssertGreaterThan(visible?.width ?? 0, 0)
            XCTAssertGreaterThan(visible?.height ?? 0, 0)
        }
    }
}
```

The last test reads the real `NSScreen` list. It accepts both a machine with screens and a headless one, so it never depends on the developer's display setup.

- [ ] **Step 6: Run the ScreenGeometry tests and confirm they fail**

Run from the repo root:

```bash
cd Tofu && xcodegen generate && xcodebuild -project Tofu.xcodeproj -scheme Tofu -destination 'platform=macOS' test -only-testing:TofuTests/ScreenGeometryTests 2>&1 | tail -30
```

Expected: the test target does not compile. The log contains `error: cannot find 'ScreenGeometry' in scope` and `error: cannot find 'ChromeBounds' in scope`. The last line is `** TEST FAILED **`.

- [ ] **Step 7: Implement ScreenGeometry**

Create `Tofu/Tofu/System/ScreenGeometry.swift`:

```swift
import AppKit

/// Chrome AppleScript window `bounds` {left, top, right, bottom}: origin at the top-left
/// of the primary screen, y grows downward, whole points.
struct ChromeBounds: Equatable {
    var left: Int
    var top: Int
    var right: Int
    var bottom: Int
}

/// Converts Cocoa screen rects into Chrome's AppleScript coordinate space (spec §7).
enum ScreenGeometry {
    /// Cocoa rect -> Chrome AppleScript bounds (top-left origin of primary screen, y down).
    static func chromeBounds(for rect: CGRect, primaryHeight: CGFloat) -> ChromeBounds {
        ChromeBounds(left: wholePoints(rect.minX),
                     top: wholePoints(primaryHeight - rect.maxY),
                     right: wholePoints(rect.maxX),
                     bottom: wholePoints(primaryHeight - rect.minY))
    }

    /// Visible frame (menu bar and Dock excluded) of the main screen, else the first screen; nil with no screen.
    @MainActor static func mainVisibleFrame() -> CGRect? {
        (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
    }

    /// Height of the primary screen (`NSScreen.screens[0]`), or 0 when there is no screen.
    @MainActor static func primaryHeight() -> CGFloat {
        NSScreen.screens.first?.frame.height ?? 0
    }

    /// Largest magnitude we convert; real screens are far smaller. Keeps `Int(_:)` from trapping.
    private static let limit: CGFloat = 1_000_000

    /// Rounds to the nearest whole point. Non-finite values become 0 and huge values are clamped.
    private static func wholePoints(_ value: CGFloat) -> Int {
        guard value.isFinite else { return 0 }
        return Int(min(max(value.rounded(), -limit), limit))
    }
}
```

- [ ] **Step 8: Run both test classes and confirm they pass**

Run from the repo root:

```bash
cd Tofu && xcodegen generate && xcodebuild -project Tofu.xcodeproj -scheme Tofu -destination 'platform=macOS' test -only-testing:TofuTests/LayoutEngineTests -only-testing:TofuTests/ScreenGeometryTests 2>&1 | tail -30
```

Expected: `Test Suite 'LayoutEngineTests' passed` (9 tests), `Test Suite 'ScreenGeometryTests' passed` (7 tests), `Executed 16 tests, with 0 failures (0 unexpected)`, and the last line `** TEST SUCCEEDED **`.

- [ ] **Step 9: Commit**

```bash
cd "$(git rev-parse --show-toplevel)" && git add Tofu/Tofu/Engine/LayoutEngine.swift Tofu/Tofu/System/ScreenGeometry.swift Tofu/TofuTests/LayoutEngineTests.swift Tofu/TofuTests/ScreenGeometryTests.swift Tofu/Tofu.xcodeproj && git commit -F - <<'EOF'
Add LayoutEngine and ScreenGeometry for window tiling

Presets split the visible frame into whole-point zones; the last zone
absorbs the remainder. ScreenGeometry converts Cocoa rects to Chrome
AppleScript bounds.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

Expected: `git log -1 --stat` shows the 4 new Swift files plus `project.pbxproj` changes.

### Task 4: DomainMatcher

Pure URL and host logic for spec §8. Three callers use it:

- `ChromeController` (Task 8) opens each site through `normalizedURL` and reports closed tabs through `host(of:)`.
- `SessionEngine` (Task 10) computes `allowedDomains` once at lock-in.
- The tab watch calls `isAllowed` for every tab URL every 2 s.

This task covers **Review Focus 2**: sites typed without a scheme or with `www.`/uppercase, subdomains, look-alike hosts, and blank tabs that must never be closed.

Behavior details beyond the spec text. The tests below pin each one down:

- **Scheme detection.** A scheme counts only when the string starts with `letters/digits/+-.` followed by `://`. `localhost:3000` therefore becomes `https://localhost:3000`, and `piazza.com/r?next=https://x.com` becomes `https://piazza.com/r?next=https://x.com`.
- **Chrome internals.** `chrome-search://`, `chrome-untrusted://` and `devtools://` are treated as Chrome internals, like `chrome://`, `chrome-extension://` and `about:`. Chrome's new-tab page can be `chrome-search://local-ntp/local-ntp.html` when a third-party search engine is set, and spec §8 says "we don't fight Chrome internals".
- **Unparseable or hostless URLs.** `isAllowed` parses the tab URL as-is, never adding a scheme. Chrome always reports absolute URLs, so a string without a host (`%%%`, `not a url`, `file:///Users/me/notes.pdf`, `data:text/plain,hi`) counts as "cannot be parsed" and is allowed.
- **Normalizing `allowed`.** `isAllowed` normalizes each entry before matching, so callers may pass raw user input.
- **Foundation parsing (macOS 14+).** `URL(string:)` returns nil for hosts with spaces or `%` (`https://not a url`, `https://%%%`). `normalizedURL` relies on that to reject garbage. The editor validation in Task 13 relies on it too.

**Files:**
- Create: `Tofu/Tofu/Engine/DomainMatcher.swift`
- Test: `Tofu/TofuTests/DomainMatcherTests.swift`
- Modify (regenerated by `xcodegen generate`): `Tofu/Tofu.xcodeproj`

**Interfaces:**
- Consumes: nothing from earlier tasks (Foundation only).
- Produces:
  ```swift
  enum DomainMatcher {
      /// lowercase, trim whitespace, strip leading "www." and trailing ".".
      static func normalize(_ domain: String) -> String
      /// Adds "https://" when the string has no scheme. nil if no host results.
      static func normalizedURL(_ string: String) -> URL?
      /// Normalized host of a URL string, or nil.
      static func host(of urlString: String) -> String?
      /// Hosts of sites + extra domains, normalized, deduplicated, order preserved, empties dropped.
      static func allowedDomains(sites: [String], extra: [String]) -> [String]
      /// See spec §8.
      static func isAllowed(_ urlString: String, allowed: [String]) -> Bool
  }
  ```

- [ ] **Step 1: Write the failing DomainMatcher tests**

Create `Tofu/TofuTests/DomainMatcherTests.swift`:

```swift
import XCTest
@testable import Tofu

final class DomainMatcherTests: XCTestCase {
    private let allowed = ["youtube.com", "piazza.com"]

    // MARK: normalize

    func testNormalizeLowercasesTrimsAndStripsWwwAndTrailingDots() {
        XCTAssertEqual(DomainMatcher.normalize("WWW.Piazza.com."), "piazza.com")
        XCTAssertEqual(DomainMatcher.normalize("  YouTube.com \n"), "youtube.com")
        XCTAssertEqual(DomainMatcher.normalize("example.org.."), "example.org")
        XCTAssertEqual(DomainMatcher.normalize("docs.python.org"), "docs.python.org")
        XCTAssertEqual(DomainMatcher.normalize("wwwexample.com"), "wwwexample.com")
        XCTAssertEqual(DomainMatcher.normalize(""), "")
    }

    // MARK: normalizedURL

    func testNormalizedURLAddsHTTPSWhenTheSchemeIsMissing() {
        XCTAssertEqual(DomainMatcher.normalizedURL("piazza.com/class/x")?.absoluteString,
                       "https://piazza.com/class/x")
        XCTAssertEqual(DomainMatcher.normalizedURL("Piazza.com/class/x")?.scheme, "https")
        XCTAssertEqual(DomainMatcher.normalizedURL("localhost:3000")?.absoluteString, "https://localhost:3000")
        XCTAssertEqual(DomainMatcher.normalizedURL("piazza.com/r?next=https://x.com")?.host(percentEncoded: false),
                       "piazza.com")
    }

    func testNormalizedURLKeepsAnExistingSchemeAndTrims() {
        XCTAssertEqual(DomainMatcher.normalizedURL("http://example.com/a")?.absoluteString, "http://example.com/a")
        XCTAssertEqual(DomainMatcher.normalizedURL("  https://cs128.org/  ")?.absoluteString, "https://cs128.org/")
    }

    func testNormalizedURLIsNilForBlankOrHostlessInput() {
        XCTAssertNil(DomainMatcher.normalizedURL("  "))
        XCTAssertNil(DomainMatcher.normalizedURL(""))
        XCTAssertNil(DomainMatcher.normalizedURL("https://"))
        XCTAssertNil(DomainMatcher.normalizedURL("not a url"))
        XCTAssertNil(DomainMatcher.normalizedURL("%%%"))
    }

    // MARK: host(of:)

    func testHostOfNormalizesAndAcceptsMissingScheme() {
        XCTAssertEqual(DomainMatcher.host(of: "https://www.YouTube.com/watch?v=x"), "youtube.com")
        XCTAssertEqual(DomainMatcher.host(of: "piazza.com/class/x"), "piazza.com")
        XCTAssertEqual(DomainMatcher.host(of: "Piazza.com/class/x"), "piazza.com")
        XCTAssertEqual(DomainMatcher.host(of: "http://localhost:3000/app"), "localhost")
        XCTAssertEqual(DomainMatcher.host(of: "https://m.youtube.com./feed"), "m.youtube.com")
        XCTAssertNil(DomainMatcher.host(of: ""))
        XCTAssertNil(DomainMatcher.host(of: "   "))
        XCTAssertNil(DomainMatcher.host(of: "https://"))
    }

    // MARK: allowedDomains

    func testAllowedDomainsMergesSitesAndExtrasNormalizedAndDeduplicated() {
        let domains = DomainMatcher.allowedDomains(
            sites: ["https://www.YouTube.com/watch?v=x", "Piazza.com/class/x"],
            extra: ["WWW.StackOverflow.com.", "piazza.com", "youtube.com", "", "   ", "docs.python.org/3/"])
        XCTAssertEqual(domains, ["youtube.com", "piazza.com", "stackoverflow.com", "docs.python.org"])
    }

    func testAllowedDomainsOfNothingIsEmpty() {
        XCTAssertEqual(DomainMatcher.allowedDomains(sites: [], extra: []), [])
        XCTAssertEqual(DomainMatcher.allowedDomains(sites: [""], extra: ["  "]), [])
    }

    // MARK: isAllowed

    func testExactHostIsAllowed() {
        XCTAssertTrue(DomainMatcher.isAllowed("https://youtube.com/watch?v=1", allowed: allowed))
        XCTAssertTrue(DomainMatcher.isAllowed("https://piazza.com/class/x", allowed: allowed))
        XCTAssertTrue(DomainMatcher.isAllowed("https://www.piazza.com/", allowed: allowed))
    }

    func testSubdomainIsAllowed() {
        XCTAssertTrue(DomainMatcher.isAllowed("https://m.youtube.com/feed", allowed: allowed))
        XCTAssertTrue(DomainMatcher.isAllowed("https://a.b.piazza.com/", allowed: allowed))
    }

    func testLookalikeHostsAreNotAllowed() {
        XCTAssertFalse(DomainMatcher.isAllowed("https://notyoutube.com/", allowed: allowed))
        XCTAssertFalse(DomainMatcher.isAllowed("https://youtube.com.evil.com/", allowed: allowed))
        XCTAssertFalse(DomainMatcher.isAllowed("https://youtube.com@evil.com/", allowed: allowed))
    }

    func testDifferentDomainIsNotAllowed() {
        XCTAssertFalse(DomainMatcher.isAllowed("https://www.reddit.com/r/all", allowed: allowed))
        XCTAssertFalse(DomainMatcher.isAllowed("http://twitter.com", allowed: allowed))
    }

    func testBlankTabsAndChromeInternalPagesAreAllowed() {
        let internalPages = [
            "chrome://newtab", "chrome://newtab/", "chrome://new-tab-page/", "chrome://settings",
            "chrome://settings/privacy", "Chrome://Settings", "about:blank", "", "   ",
            "chrome-extension://abcdefghijklmnop/popup.html", "chrome-search://local-ntp/local-ntp.html",
        ]
        for url in internalPages {
            XCTAssertTrue(DomainMatcher.isAllowed(url, allowed: allowed), "\(url.debugDescription) should be allowed")
        }
    }

    func testUnparseableURLsAreAllowed() {
        XCTAssertTrue(DomainMatcher.isAllowed("%%%", allowed: allowed))
        XCTAssertTrue(DomainMatcher.isAllowed("not a url", allowed: allowed))
        XCTAssertTrue(DomainMatcher.isAllowed("https://", allowed: allowed))
    }

    func testUppercaseHostIsAllowed() {
        XCTAssertTrue(DomainMatcher.isAllowed("HTTPS://WWW.YOUTUBE.COM/WATCH?V=1", allowed: allowed))
        XCTAssertTrue(DomainMatcher.isAllowed("https://M.YouTube.COM/", allowed: allowed))
    }

    func testPortIsIgnored() {
        XCTAssertTrue(DomainMatcher.isAllowed("http://localhost:3000/app", allowed: ["localhost"]))
        XCTAssertFalse(DomainMatcher.isAllowed("http://localhost:3000/app", allowed: ["piazza.com"]))
        XCTAssertTrue(DomainMatcher.isAllowed("https://piazza.com:8443/x", allowed: allowed))
    }

    func testAllowedEntriesAreNormalizedBeforeMatching() {
        XCTAssertTrue(DomainMatcher.isAllowed("https://youtube.com/", allowed: ["WWW.YouTube.com."]))
        XCTAssertFalse(DomainMatcher.isAllowed("https://youtube.com/", allowed: ["", "  "]))
    }

    func testEmptyAllowListClosesWebPagesButKeepsBlankTabs() {
        XCTAssertFalse(DomainMatcher.isAllowed("https://youtube.com/", allowed: []))
        XCTAssertTrue(DomainMatcher.isAllowed("chrome://newtab/", allowed: []))
    }

    /// Review Focus 2: a site typed without a scheme, with uppercase letters.
    func testSiteTypedWithoutSchemeOpensAsHTTPSAndAllowsItsDomain() {
        XCTAssertEqual(DomainMatcher.normalizedURL("Piazza.com/class/x")?.absoluteString, "https://Piazza.com/class/x")
        let domains = DomainMatcher.allowedDomains(sites: ["Piazza.com/class/x"], extra: [])
        XCTAssertEqual(domains, ["piazza.com"])
        XCTAssertTrue(DomainMatcher.isAllowed("https://piazza.com/class/x/post/42", allowed: domains))
        XCTAssertTrue(DomainMatcher.isAllowed("https://www.piazza.com/", allowed: domains))
        XCTAssertTrue(DomainMatcher.isAllowed("https://cdn.piazza.com/file.pdf", allowed: domains))
        XCTAssertTrue(DomainMatcher.isAllowed("chrome://newtab/", allowed: domains))
        XCTAssertFalse(DomainMatcher.isAllowed("https://notpiazza.com/", allowed: domains))
        XCTAssertFalse(DomainMatcher.isAllowed("https://youtube.com/", allowed: domains))
    }
}
```

- [ ] **Step 2: Run the DomainMatcher tests and confirm they fail**

Run from the repo root:

```bash
cd Tofu && xcodegen generate && xcodebuild -project Tofu.xcodeproj -scheme Tofu -destination 'platform=macOS' test -only-testing:TofuTests/DomainMatcherTests 2>&1 | tail -30
```

Expected: the test target does not compile. The log contains `error: cannot find 'DomainMatcher' in scope`, and the last line is `** TEST FAILED **`.

- [ ] **Step 3: Implement DomainMatcher**

Create `Tofu/Tofu/Engine/DomainMatcher.swift`:

```swift
import Foundation

/// Decides which Chrome tabs belong to the current subject (spec §8).
enum DomainMatcher {
    /// Chrome's own pages and blank tabs. Tabs whose URL starts with one of these are never closed.
    private static let internalPrefixes = [
        "chrome://", "chrome-extension://", "chrome-search://", "chrome-untrusted://", "devtools://", "about:",
    ]

    /// lowercase, trim whitespace, strip leading "www." and trailing ".".
    static func normalize(_ domain: String) -> String {
        var result = domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while result.hasSuffix(".") {
            result.removeLast()
        }
        if result.hasPrefix("www.") {
            result.removeFirst(4)
        }
        return result
    }

    /// Adds "https://" when the string has no scheme. nil if no host results.
    static func normalizedURL(_ string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let candidate = hasScheme(trimmed) ? trimmed : "https://" + trimmed
        guard let url = URL(string: candidate),
              let host = url.host(percentEncoded: false),
              !host.isEmpty else { return nil }
        return url
    }

    /// Normalized host of a URL string, or nil.
    static func host(of urlString: String) -> String? {
        guard let rawHost = normalizedURL(urlString)?.host(percentEncoded: false) else { return nil }
        let host = normalize(rawHost)
        return host.isEmpty ? nil : host
    }

    /// Hosts of sites + extra domains, normalized, deduplicated, order preserved, empties dropped.
    static func allowedDomains(sites: [String], extra: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for entry in sites + extra {
            guard let domain = host(of: entry), seen.insert(domain).inserted else { continue }
            result.append(domain)
        }
        return result
    }

    /// See spec §8. Blank, Chrome-internal and unparseable URLs are allowed; otherwise the
    /// normalized host must equal an allowed domain or end with "." + that domain.
    static func isAllowed(_ urlString: String, allowed: [String]) -> Bool {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        let lowered = trimmed.lowercased()
        if internalPrefixes.contains(where: { lowered.hasPrefix($0) }) { return true }
        guard let rawHost = URL(string: trimmed)?.host(percentEncoded: false) else { return true }
        let host = normalize(rawHost)
        if host.isEmpty { return true }
        return allowed.contains { entry in
            let domain = normalize(entry)
            return !domain.isEmpty && (host == domain || host.hasSuffix("." + domain))
        }
    }

    /// True when the string starts with an RFC 3986 scheme followed by "://", e.g. "https://".
    private static func hasScheme(_ string: String) -> Bool {
        guard let separator = string.range(of: "://") else { return false }
        let scheme = string[string.startIndex..<separator.lowerBound]
        guard let first = scheme.first, first.isASCII, first.isLetter else { return false }
        return scheme.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == ".") }
    }
}
```

- [ ] **Step 4: Run the DomainMatcher tests and confirm they pass**

Run from the repo root:

```bash
cd Tofu && xcodegen generate && xcodebuild -project Tofu.xcodeproj -scheme Tofu -destination 'platform=macOS' test -only-testing:TofuTests/DomainMatcherTests 2>&1 | tail -30
```

Expected: `Test Suite 'DomainMatcherTests' passed`, `Executed 18 tests, with 0 failures (0 unexpected)`, and the last line `** TEST SUCCEEDED **`.

If `testNormalizedURLIsNilForBlankOrHostlessInput` or `testUnparseableURLsAreAllowed` fails, Foundation's URL parsing differs from the macOS 14+ behavior described above. Check that the deployment target is `14.0` and that you are building with the macOS SDK from Xcode 16.3. Do not loosen the assertions.

- [ ] **Step 5: Run the full test suite**

Run from the repo root:

```bash
cd Tofu && xcodegen generate && xcodebuild -project Tofu.xcodeproj -scheme Tofu -destination 'platform=macOS' test 2>&1 | tail -30
```

Expected: every suite passes, including the Task 1–2 suites plus `LayoutEngineTests`, `ScreenGeometryTests` and `DomainMatcherTests`. The output shows `0 failures`, and the last line is `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
cd "$(git rev-parse --show-toplevel)" && git add Tofu/Tofu/Engine/DomainMatcher.swift Tofu/TofuTests/DomainMatcherTests.swift Tofu/Tofu.xcodeproj && git commit -F - <<'EOF'
Add DomainMatcher for Chrome tab allow-listing

Normalizes typed sites to https URLs, derives allowed domains (www and
trailing dots stripped, deduplicated) and decides per tab URL whether it
is on-topic. Blank tabs and Chrome internals are always allowed.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

Expected: `git log -1 --stat` shows the 2 new Swift files plus `project.pbxproj` changes.

### Task 5: TimeFormat, DiscordMessages and ChannelPicker

Three pure units with no AppKit: duration formatting (timers, stats and Discord text), the exact Discord message texts from spec §9, and the channel-candidate order used when posting to a guild. Each gets its own red/green/commit cycle.

**Files:**
- Create: `Tofu/Tofu/Engine/TimeFormat.swift`
- Create: `Tofu/Tofu/Discord/DiscordMessages.swift`
- Create: `Tofu/Tofu/Discord/ChannelPicker.swift` (also holds `DiscordChannel`)
- Test: `Tofu/TofuTests/TimeFormatTests.swift`
- Test: `Tofu/TofuTests/DiscordMessagesTests.swift`
- Test: `Tofu/TofuTests/ChannelPickerTests.swift`

**Interfaces:**
- Consumes:
  - `enum SessionMode: Codable, Hashable { case open; case goal(minutes: Int); var goalMinutes: Int? { get }; var goalSeconds: TimeInterval? { get } }` (Task 2, `Models/Session.swift`)
- Produces:
  ```swift
  enum TimeFormat {
      /// Floor to minutes: 0 -> "0m", 59*60 -> "59m", 3600 -> "1h 0m", 4800 -> "1h 20m". Negative -> "0m".
      static func short(_ seconds: TimeInterval) -> String
      /// Floor to seconds: < 1h -> "MM:SS" ("00:00", "59:59"); >= 1h -> "H:MM:SS" ("1:00:00"). Negative -> "00:00".
      static func clock(_ seconds: TimeInterval) -> String
  }

  enum DiscordMessages {
      static func start(name: String, subject: String, mode: SessionMode) -> String
      static func completed(name: String, subject: String, duration: TimeInterval, attempts: Int, tabs: Int) -> String
      static func bailed(name: String, subject: String, duration: TimeInterval, goalMinutes: Int, attempts: Int) -> String
  }

  struct DiscordChannel: Decodable, Equatable {
      let id: String
      let name: String?
      let type: Int
      let position: Int?
  }

  enum ChannelPicker {
      static let preferredNames = ["lock-in", "locked-in", "lockin", "accountability"]
      /// Text channels only (type == 0). Order: cached id (if present & text), preferred names in list order,
      /// then remaining text channels by position (nil last), ties by id. No duplicates.
      static func candidates(from channels: [DiscordChannel], cachedID: String?) -> [String]
  }
  ```
  Later consumers: `DiscordClient` (Task 6) uses `DiscordChannel` and `ChannelPicker`; `SessionEngine` (Task 10) uses `DiscordMessages`; the timer and stats views (Tasks 13, 14, 16) use `TimeFormat`.

- [ ] **Step 1: Write the failing TimeFormat tests**

Create `Tofu/TofuTests/TimeFormatTests.swift`:

```swift
import XCTest
@testable import Tofu

final class TimeFormatTests: XCTestCase {
    func testShortFloorsToMinutes() {
        XCTAssertEqual(TimeFormat.short(0), "0m")
        XCTAssertEqual(TimeFormat.short(59), "0m")
        XCTAssertEqual(TimeFormat.short(59 * 60 + 59), "59m")
        XCTAssertEqual(TimeFormat.short(3600), "1h 0m")
        XCTAssertEqual(TimeFormat.short(4800), "1h 20m")
        XCTAssertEqual(TimeFormat.short(10 * 3600 + 5 * 60 + 30), "10h 5m")
    }

    func testShortNegativeAndNonFiniteAreZero() {
        XCTAssertEqual(TimeFormat.short(-5), "0m")
        XCTAssertEqual(TimeFormat.short(.nan), "0m")
        XCTAssertEqual(TimeFormat.short(-.infinity), "0m")
    }

    func testClockUnderAnHourIsMinutesSeconds() {
        XCTAssertEqual(TimeFormat.clock(0), "00:00")
        XCTAssertEqual(TimeFormat.clock(5.9), "00:05")
        XCTAssertEqual(TimeFormat.clock(65), "01:05")
        XCTAssertEqual(TimeFormat.clock(3599), "59:59")
    }

    func testClockFromAnHourIncludesHours() {
        XCTAssertEqual(TimeFormat.clock(3600), "1:00:00")
        XCTAssertEqual(TimeFormat.clock(36000 + 61), "10:01:01")
    }

    func testClockNegativeAndNonFiniteAreZero() {
        XCTAssertEqual(TimeFormat.clock(-1), "00:00")
        XCTAssertEqual(TimeFormat.clock(.nan), "00:00")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run from the repo root:

```bash
(cd Tofu && xcodegen generate && xcodebuild -project Tofu.xcodeproj -scheme Tofu -destination 'platform=macOS' test -only-testing:TofuTests/TimeFormatTests 2>&1 | tail -30)
```

Expected: the test target does not compile. The output contains `error: cannot find 'TimeFormat' in scope` and ends with `** TEST FAILED **`.

- [ ] **Step 3: Implement TimeFormat**

Create `Tofu/Tofu/Engine/TimeFormat.swift`:

```swift
import Foundation

/// Duration formatting shared by the timers, stats and Discord messages.
enum TimeFormat {
    /// Upper bound for formatting so absurd inputs can never overflow `Int` (about 31 years).
    private static let maxSeconds: TimeInterval = 1_000_000_000

    /// Floor to minutes: 0 -> "0m", 59*60 -> "59m", 3600 -> "1h 0m", 4800 -> "1h 20m". Negative -> "0m".
    static func short(_ seconds: TimeInterval) -> String {
        let totalMinutes = wholeSeconds(seconds) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    /// Floor to seconds: < 1h -> "MM:SS" ("00:00", "59:59"); >= 1h -> "H:MM:SS" ("1:00:00"). Negative -> "00:00".
    static func clock(_ seconds: TimeInterval) -> String {
        let total = wholeSeconds(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return "\(hours):\(twoDigits(minutes)):\(twoDigits(secs))"
        }
        return "\(twoDigits(minutes)):\(twoDigits(secs))"
    }

    /// Whole, non-negative seconds. NaN, infinities and negatives become 0.
    private static func wholeSeconds(_ seconds: TimeInterval) -> Int {
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return Int(min(seconds, maxSeconds).rounded(.down))
    }

    private static func twoDigits(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run from the repo root:

```bash
(cd Tofu && xcodegen generate && xcodebuild -project Tofu.xcodeproj -scheme Tofu -destination 'platform=macOS' test -only-testing:TofuTests/TimeFormatTests 2>&1 | tail -30)
```

Expected: all 5 `TimeFormatTests` cases pass, and the output ends with `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
cd "$(git rev-parse --show-toplevel)" && git add Tofu/Tofu/Engine/TimeFormat.swift Tofu/TofuTests/TimeFormatTests.swift Tofu/Tofu.xcodeproj
git commit -F - <<'EOF'
Add TimeFormat for durations and timer clocks

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

- [ ] **Step 6: Write the failing DiscordMessages tests**

These strings must match spec §9 exactly. Copy them byte for byte: `·` is U+00B7, `×` is U+00D7, and the white flag `🏳️` is U+1F3F3 followed by the variation selector U+FE0F. The last assertion in `testBailed` checks the flag's scalars, so a dropped selector fails loudly.

Create `Tofu/TofuTests/DiscordMessagesTests.swift`:

```swift
import XCTest
@testable import Tofu

final class DiscordMessagesTests: XCTestCase {
    func testStartOpenMode() {
        XCTAssertEqual(DiscordMessages.start(name: "Alex", subject: "CS128", mode: .open),
                       "🔒 **Alex** is locked in on **CS128**")
    }

    func testStartGoalModeAppendsGoalInMinutes() {
        XCTAssertEqual(DiscordMessages.start(name: "Alex", subject: "CS128", mode: .goal(minutes: 50)),
                       "🔒 **Alex** is locked in on **CS128** (goal 50m)")
    }

    func testStartGoalModeOverAnHour() {
        let text = DiscordMessages.start(name: "Alex", subject: "MATH241", mode: .goal(minutes: 90))
        XCTAssertEqual(text, "🔒 **Alex** is locked in on **MATH241** (goal 1h 30m)")
        XCTAssertTrue(text.hasSuffix("(goal 1h 30m)"))
    }

    func testCompleted() {
        let text = DiscordMessages.completed(name: "Alex", subject: "CS128", duration: 4800 + 59,
                                             attempts: 3, tabs: 2)
        XCTAssertEqual(text,
                       "✅ **Alex** locked in on **CS128** for **1h 20m** · tried other apps **3×** · closed **2** tabs")
    }

    func testCompletedZeroDuration() {
        let text = DiscordMessages.completed(name: "Alex", subject: "CS128", duration: 30, attempts: 0, tabs: 0)
        XCTAssertEqual(text,
                       "✅ **Alex** locked in on **CS128** for **0m** · tried other apps **0×** · closed **0** tabs")
    }

    func testBailed() {
        let text = DiscordMessages.bailed(name: "Alex", subject: "CS128", duration: 12 * 60 + 40,
                                          goalMinutes: 50, attempts: 4)
        XCTAssertEqual(text,
                       "🏳️ **Alex** bailed on **CS128** after **12m** (goal 50m) · tried other apps **4×**")
        // The white flag must keep its emoji variation selector.
        XCTAssertTrue(text.unicodeScalars.starts(with: "\u{1F3F3}\u{FE0F} ".unicodeScalars))
    }

    func testBailedLongGoal() {
        let text = DiscordMessages.bailed(name: "Sam", subject: "MATH241", duration: 3600 + 60,
                                          goalMinutes: 90, attempts: 1)
        XCTAssertEqual(text,
                       "🏳️ **Sam** bailed on **MATH241** after **1h 1m** (goal 1h 30m) · tried other apps **1×**")
    }
}
```

- [ ] **Step 7: Run the tests to verify they fail**

Run from the repo root:

```bash
(cd Tofu && xcodegen generate && xcodebuild -project Tofu.xcodeproj -scheme Tofu -destination 'platform=macOS' test -only-testing:TofuTests/DiscordMessagesTests 2>&1 | tail -30)
```

Expected: the output contains `error: cannot find 'DiscordMessages' in scope` and ends with `** TEST FAILED **`.

- [ ] **Step 8: Implement DiscordMessages**

Create `Tofu/Tofu/Discord/DiscordMessages.swift`:

```swift
import Foundation

/// Exact Discord message texts (spec §9). Durations always go through `TimeFormat.short`.
enum DiscordMessages {
    /// "🔒 **{name}** is locked in on **{subject}**" + " (goal {TimeFormat.short(goal)})" in goal mode.
    static func start(name: String, subject: String, mode: SessionMode) -> String {
        let base = "🔒 **\(name)** is locked in on **\(subject)**"
        guard let goal = mode.goalSeconds else { return base }
        return base + " (goal \(TimeFormat.short(goal)))"
    }

    /// "✅ **{name}** locked in on **{subject}** for **{dur}** · tried other apps **{attempts}×** · closed **{tabs}** tabs"
    static func completed(name: String, subject: String, duration: TimeInterval, attempts: Int, tabs: Int) -> String {
        "✅ **\(name)** locked in on **\(subject)** for **\(TimeFormat.short(duration))**"
            + " · tried other apps **\(attempts)×** · closed **\(tabs)** tabs"
    }

    /// "🏳️ **{name}** bailed on **{subject}** after **{dur}** (goal {goal}) · tried other apps **{attempts}×**"
    /// The flag is written as escapes (U+1F3F3 U+FE0F) so the variation selector cannot be lost in copy/paste.
    static func bailed(name: String, subject: String, duration: TimeInterval, goalMinutes: Int, attempts: Int) -> String {
        let goal = TimeFormat.short(TimeInterval(goalMinutes) * 60)
        return "\u{1F3F3}\u{FE0F} **\(name)** bailed on **\(subject)** after **\(TimeFormat.short(duration))**"
            + " (goal \(goal)) · tried other apps **\(attempts)×**"
    }
}
```

- [ ] **Step 9: Run the tests to verify they pass**

Run from the repo root:

```bash
(cd Tofu && xcodegen generate && xcodebuild -project Tofu.xcodeproj -scheme Tofu -destination 'platform=macOS' test -only-testing:TofuTests/DiscordMessagesTests 2>&1 | tail -30)
```

Expected: all 7 `DiscordMessagesTests` cases pass, and the output ends with `** TEST SUCCEEDED **`.

- [ ] **Step 10: Commit**

```bash
cd "$(git rev-parse --show-toplevel)" && git add Tofu/Tofu/Discord/DiscordMessages.swift Tofu/TofuTests/DiscordMessagesTests.swift Tofu/Tofu.xcodeproj
git commit -F - <<'EOF'
Add DiscordMessages with the exact spec texts

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

- [ ] **Step 11: Write the failing ChannelPicker tests**

Ordering rules under test:
1. The cached channel comes first, but only if it is still in the list and is a text channel (`type == 0`).
2. Next come the preferred names, in `preferredNames` order (case-insensitive).
3. Then every other text channel, by `position` ascending, with `nil` positions last.
4. Ties are broken by snowflake id in numeric order (`"99"` before `"100"`).
5. Voice (2), category (4) and every other non-text type are excluded. No id appears twice.

Create `Tofu/TofuTests/ChannelPickerTests.swift`:

```swift
import XCTest
@testable import Tofu

final class ChannelPickerTests: XCTestCase {
    private func text(_ id: String, _ name: String, _ position: Int?) -> DiscordChannel {
        DiscordChannel(id: id, name: name, type: 0, position: position)
    }

    func testCachedChannelFirstWhenPresentAndText() {
        let channels = [text("10", "general", 0), text("11", "random", 1), text("12", "lock-in", 2)]
        XCTAssertEqual(ChannelPicker.candidates(from: channels, cachedID: "11"), ["11", "12", "10"])
    }

    func testCachedChannelIgnoredWhenMissing() {
        let channels = [text("10", "general", 0), text("12", "lock-in", 2)]
        XCTAssertEqual(ChannelPicker.candidates(from: channels, cachedID: "99"), ["12", "10"])
    }

    func testCachedChannelIgnoredWhenVoice() {
        let channels = [text("10", "general", 0), DiscordChannel(id: "20", name: "Study Room", type: 2, position: 0)]
        XCTAssertEqual(ChannelPicker.candidates(from: channels, cachedID: "20"), ["10"])
    }

    func testPreferredNamesInListOrder() {
        let channels = [
            text("1", "accountability", 0),
            text("2", "general", 1),
            text("3", "lockin", 2),
            text("4", "lock-in", 3),
            text("5", "locked-in", 4),
        ]
        XCTAssertEqual(ChannelPicker.candidates(from: channels, cachedID: nil), ["4", "5", "3", "1", "2"])
    }

    func testPreferredNameMatchIgnoresCase() {
        let channels = [text("1", "general", 0), text("2", "Lock-In", 1)]
        XCTAssertEqual(ChannelPicker.candidates(from: channels, cachedID: nil), ["2", "1"])
    }

    func testRemainingByPositionWithNilLast() {
        let channels = [text("1", "c", 3), text("2", "no-position", nil), text("3", "a", 1), text("4", "b", 2)]
        XCTAssertEqual(ChannelPicker.candidates(from: channels, cachedID: nil), ["3", "4", "1", "2"])
    }

    func testPositionTiesBrokenByNumericID() {
        let channels = [text("100", "x", 1), text("99", "y", 1), text("5", "z", nil), text("40", "w", nil)]
        XCTAssertEqual(ChannelPicker.candidates(from: channels, cachedID: nil), ["99", "100", "5", "40"])
    }

    func testVoiceAndCategoryExcluded() {
        let channels = [
            DiscordChannel(id: "1", name: "Voice", type: 2, position: 0),
            DiscordChannel(id: "2", name: "TEXT CHANNELS", type: 4, position: 0),
            DiscordChannel(id: "3", name: "lock-in", type: 2, position: 1),
            text("4", "general", 5),
        ]
        XCTAssertEqual(ChannelPicker.candidates(from: channels, cachedID: nil), ["4"])
    }

    func testNoDuplicatesWhenCachedIsAlsoPreferred() {
        let channels = [text("1", "general", 0), text("2", "lock-in", 1)]
        let result = ChannelPicker.candidates(from: channels, cachedID: "2")
        XCTAssertEqual(result, ["2", "1"])
        XCTAssertEqual(Set(result).count, result.count)
    }

    func testEmptyInputGivesNoCandidates() {
        XCTAssertEqual(ChannelPicker.candidates(from: [], cachedID: "1"), [])
    }

    func testDecodesDiscordChannelJSON() throws {
        let json = """
        [
          {"id": "10", "type": 0, "guild_id": "1", "position": 2, "name": "general", "nsfw": false},
          {"id": "11", "type": 4, "guild_id": "1", "position": 0, "name": "Text Channels"},
          {"id": "12", "type": 0, "guild_id": "1"}
        ]
        """
        let channels = try JSONDecoder().decode([DiscordChannel].self, from: Data(json.utf8))
        XCTAssertEqual(channels, [
            DiscordChannel(id: "10", name: "general", type: 0, position: 2),
            DiscordChannel(id: "11", name: "Text Channels", type: 4, position: 0),
            DiscordChannel(id: "12", name: nil, type: 0, position: nil),
        ])
    }
}
```

- [ ] **Step 12: Run the tests to verify they fail**

Run from the repo root:

```bash
(cd Tofu && xcodegen generate && xcodebuild -project Tofu.xcodeproj -scheme Tofu -destination 'platform=macOS' test -only-testing:TofuTests/ChannelPickerTests 2>&1 | tail -30)
```

Expected: the output contains `error: cannot find type 'DiscordChannel' in scope` and ends with `** TEST FAILED **`. The compiler stops at this missing type in the helper's signature, so `ChannelPicker` may not be reported yet.

- [ ] **Step 13: Implement DiscordChannel and ChannelPicker**

Create `Tofu/Tofu/Discord/ChannelPicker.swift`:

```swift
import Foundation

/// One entry of `GET /guilds/{id}/channels`. Unknown JSON fields are ignored.
struct DiscordChannel: Decodable, Equatable {
    let id: String
    let name: String?
    let type: Int       // 0 = guild text; 2 = voice; 4 = category; others ignored
    let position: Int?
}

/// Chooses which channels of a guild to try when posting (spec §9).
enum ChannelPicker {
    static let preferredNames = ["lock-in", "locked-in", "lockin", "accountability"]

    /// Text channels only (type == 0). Order: cached id (if present & text), preferred names in list order,
    /// then remaining text channels by position (nil last), ties by id. No duplicates.
    static func candidates(from channels: [DiscordChannel], cachedID: String?) -> [String] {
        let textChannels = channels.filter { $0.type == 0 }.sorted(by: positionOrder)
        var result: [String] = []
        var seen = Set<String>()
        func add(_ id: String) {
            if seen.insert(id).inserted { result.append(id) }
        }

        if let cachedID, textChannels.contains(where: { $0.id == cachedID }) {
            add(cachedID)
        }
        for preferred in preferredNames {
            for channel in textChannels where channel.name?.lowercased() == preferred {
                add(channel.id)
            }
        }
        for channel in textChannels {
            add(channel.id)
        }
        return result
    }

    /// Position ascending with nil last; ties broken by snowflake id (numeric order).
    private static func positionOrder(_ a: DiscordChannel, _ b: DiscordChannel) -> Bool {
        switch (a.position, b.position) {
        case let (pa?, pb?) where pa != pb:
            return pa < pb
        case (.some, nil):
            return true
        case (nil, .some):
            return false
        default:
            return idOrder(a.id, b.id)
        }
    }

    /// Snowflakes are decimal strings without leading zeros, so shorter means smaller.
    private static func idOrder(_ a: String, _ b: String) -> Bool {
        a.count != b.count ? a.count < b.count : a < b
    }
}
```

- [ ] **Step 14: Run the Task 5 tests to verify they pass**

Run from the repo root:

```bash
(cd Tofu && xcodegen generate && xcodebuild -project Tofu.xcodeproj -scheme Tofu -destination 'platform=macOS' test -only-testing:TofuTests/ChannelPickerTests -only-testing:TofuTests/DiscordMessagesTests -only-testing:TofuTests/TimeFormatTests 2>&1 | tail -30)
```

Expected: the 11 `ChannelPickerTests`, 7 `DiscordMessagesTests` and 5 `TimeFormatTests` cases all pass, and the output ends with `** TEST SUCCEEDED **`.

- [ ] **Step 15: Commit**

```bash
cd "$(git rev-parse --show-toplevel)" && git add Tofu/Tofu/Discord/ChannelPicker.swift Tofu/TofuTests/ChannelPickerTests.swift Tofu/Tofu.xcodeproj
git commit -F - <<'EOF'
Add ChannelPicker to order Discord channel candidates

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 6: DiscordClient

The Discord REST client takes a bot token. It talks to the network only through `HTTPTransport`, so tests can script every response with `MockTransport`, and no test touches the network. This task covers **Review Focus 5** on the client side; Task 12 covers the announcer.

What the client does:

| Call | Request | Notes |
|---|---|---|
| `me()` | `GET /api/v10/users/@me` | Decodes `DiscordUser`. Used by Settings › Test connection (Task 15). |
| `guilds()` | `GET /api/v10/users/@me/guilds` | Decodes `[DiscordGuild]`. |
| `channels(guildID:)` | `GET /api/v10/guilds/{id}/channels` | Decodes `[DiscordChannel]`. |
| `post(channelID:content:)` | `POST /api/v10/channels/{id}/messages` | Body `{"content": …, "allowed_mentions": {"parse": []}}` and `Content-Type: application/json`. |

- Every request sends `Authorization: Bot <token>` and `User-Agent: DiscordBot (tofu, 1.0)`.
- On **429**, the client reads `retry_after` (seconds, as a Double) from the JSON body. If that is missing, it falls back to the `Retry-After` header, then to 1 s. The wait is clamped to 0…30 s. The client calls the injected `sleep` once and retries once.
- Any other non-2xx status, or a second 429, throws `DiscordError.http(code)`.
- A 2xx body that fails to decode throws `.decoding`. A transport failure throws `.transport(message)`.
- `broadcast` never throws:
  - If `guilds()` fails, it returns an empty report.
  - Otherwise it handles each guild in order. It calls `channels()`, then tries at most 5 `ChannelPicker` candidates, using `channelCache[guild.id]` as the cached id. The first 2xx wins.
  - A guild whose channel list fails, or whose candidates all fail, goes into `failedGuilds`.

**Files:**
- Create: `Tofu/Tofu/Discord/DiscordClient.swift`
- Create: `Tofu/TofuTests/MockTransport.swift` (shared test helper; reused by Task 12)
- Test: `Tofu/TofuTests/DiscordClientTests.swift`

**Interfaces:**
- Consumes:
  - `struct DiscordChannel: Decodable, Equatable { let id: String; let name: String?; let type: Int; let position: Int? }` (Task 5)
  - `ChannelPicker.candidates(from channels: [DiscordChannel], cachedID: String?) -> [String]` (Task 5)
- Produces:
  ```swift
  struct DiscordGuild: Decodable, Equatable { let id: String; let name: String }
  struct DiscordUser: Decodable, Equatable { let id: String; let username: String }

  enum DiscordError: Error, Equatable {
      case http(Int)
      case transport(String)
      case decoding
  }

  protocol HTTPTransport {
      func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
  }

  struct URLSessionTransport: HTTPTransport {
      func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
  }

  struct DiscordPostReport: Equatable {
      var posted: [String: String] = [:]   // guildID -> channelID
      var failedGuilds: [String] = []
  }

  final class DiscordClient {
      static let baseURL = URL(string: "https://discord.com/api/v10")!
      init(token: String, transport: HTTPTransport = URLSessionTransport(),
           sleep: @escaping (TimeInterval) async -> Void = { seconds in
               try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
           })
      func me() async throws -> DiscordUser
      func guilds() async throws -> [DiscordGuild]
      func channels(guildID: String) async throws -> [DiscordChannel]
      /// 429 -> sleep(retry_after) once and retry; other non-2xx -> DiscordError.http(code).
      func post(channelID: String, content: String) async throws
      /// Every guild: try ChannelPicker candidates (max 5) until one succeeds. Never throws.
      func broadcast(_ content: String, channelCache: [String: String]) async -> DiscordPostReport
  }
  ```
  These additive constants are not part of the binding interfaces; nothing else depends on them: `DiscordClient.userAgent`, `DiscordClient.maxCandidatesPerGuild` (5) and `DiscordClient.maxRetryAfter` (30).
  Test helper produced for Task 12: `final class MockTransport: HTTPTransport` with `init(handler: @escaping (URLRequest) -> (Int, Data))`, `requests`, `log` and `static func json(_:)`.

- [ ] **Step 1: Create the shared MockTransport test helper**

Create `Tofu/TofuTests/MockTransport.swift` exactly as follows (Task 12 reuses it unchanged):

```swift
// TofuTests/MockTransport.swift — REAL CODE (created in Task 6, reused by Task 12)
import Foundation
@testable import Tofu

/// Scripted HTTPTransport. `handler` maps each request to (statusCode, body). Records every request.
final class MockTransport: HTTPTransport {
    var handler: (URLRequest) -> (Int, Data)
    private(set) var requests: [URLRequest] = []

    init(handler: @escaping (URLRequest) -> (Int, Data)) {
        self.handler = handler
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let (status, body) = handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        return (body, response)
    }

    /// "METHOD /path" for each recorded request, e.g. "POST /api/v10/channels/1/messages".
    var log: [String] { requests.map { "\($0.httpMethod ?? "GET") \($0.url?.path ?? "")" } }

    static func json(_ string: String) -> Data { Data(string.utf8) }
}
```

- [ ] **Step 2: Write the failing DiscordClient tests**

Each Review Focus 5 scenario has a test:
- the headers and path of `me()`
- `allowed_mentions.parse == []` in the post body
- a 403 falling through to the next channel
- an all-403 guild in `failedGuilds` while another guild posts (with the 5-candidate cap)
- the cached channel tried first
- a 429 with `retry_after: 1.5` causing exactly one `sleep(1.5)` and one retry
- `.http(401)` from `me()`
- a `guilds()` failure giving an empty report

`SleepSpy` records sleeps, so no test actually waits.

Create `Tofu/TofuTests/DiscordClientTests.swift`:

```swift
import XCTest
@testable import Tofu

/// Records every sleep the client asks for, without actually waiting.
private final class SleepSpy {
    private(set) var calls: [TimeInterval] = []
    func sleep(_ seconds: TimeInterval) async { calls.append(seconds) }
}

private let okBody = MockTransport.json("{}")
private let forbiddenBody = MockTransport.json(#"{"message": "Missing Access", "code": 50001}"#)

/// Text channels with the given ids, positions 0, 1, 2... in array order, no preferred names.
private func channelsJSON(_ ids: [String]) -> Data {
    let items = ids.enumerated().map { index, id in
        #"{"id": "\#(id)", "name": "chan-\#(id)", "type": 0, "position": \#(index)}"#
    }
    return MockTransport.json("[" + items.joined(separator: ",") + "]")
}

final class DiscordClientTests: XCTestCase {
    private func makeClient(_ transport: MockTransport, sleeper: SleepSpy = SleepSpy()) -> DiscordClient {
        DiscordClient(token: "test-token", transport: transport, sleep: { await sleeper.sleep($0) })
    }

    // MARK: - Requests

    func testMeSendsAuthAndUserAgentHeadersToUsersMe() async throws {
        let transport = MockTransport { _ in (200, MockTransport.json(#"{"id": "42", "username": "lockbot", "bot": true}"#)) }
        let user = try await makeClient(transport).me()

        XCTAssertEqual(user, DiscordUser(id: "42", username: "lockbot"))
        XCTAssertEqual(transport.requests.count, 1)
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.absoluteString, "https://discord.com/api/v10/users/@me")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bot test-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "DiscordBot (tofu, 1.0)")
        XCTAssertNil(request.httpBody)
    }

    func testGuildsAndChannelsPathsAndDecoding() async throws {
        let transport = MockTransport { request in
            switch request.url?.path ?? "" {
            case "/api/v10/users/@me/guilds":
                return (200, MockTransport.json(#"[{"id": "1", "name": "Study Hall", "icon": null}]"#))
            case "/api/v10/guilds/1/channels":
                return (200, MockTransport.json(#"[{"id": "10", "name": "general", "type": 0, "position": 0}]"#))
            default:
                return (404, MockTransport.json("{}"))
            }
        }
        let client = makeClient(transport)
        let guilds = try await client.guilds()
        let channels = try await client.channels(guildID: "1")

        XCTAssertEqual(guilds, [DiscordGuild(id: "1", name: "Study Hall")])
        XCTAssertEqual(channels, [DiscordChannel(id: "10", name: "general", type: 0, position: 0)])
        XCTAssertEqual(transport.log, ["GET /api/v10/users/@me/guilds", "GET /api/v10/guilds/1/channels"])
    }

    func testPostSendsContentWithMentionsDisabled() async throws {
        let transport = MockTransport { _ in (200, MockTransport.json(#"{"id": "500"}"#)) }
        try await makeClient(transport).post(channelID: "77", content: "🔒 **Alex** is locked in on **CS128**")

        XCTAssertEqual(transport.log, ["POST /api/v10/channels/77/messages"])
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bot test-token")
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["content"] as? String, "🔒 **Alex** is locked in on **CS128**")
        let mentions = try XCTUnwrap(json["allowed_mentions"] as? [String: Any])
        let parse = try XCTUnwrap(mentions["parse"] as? [Any])
        XCTAssertTrue(parse.isEmpty)
        XCTAssertEqual(json.count, 2)
    }

    // MARK: - Errors

    func testNon2xxOnMeThrowsHTTPStatus() async {
        let transport = MockTransport { _ in (401, MockTransport.json(#"{"message": "401: Unauthorized", "code": 0}"#)) }
        do {
            _ = try await makeClient(transport).me()
            XCTFail("expected DiscordError.http(401)")
        } catch {
            XCTAssertEqual(error as? DiscordError, .http(401))
        }
    }

    func testUndecodableBodyThrowsDecoding() async {
        let transport = MockTransport { _ in (200, MockTransport.json("not json")) }
        do {
            _ = try await makeClient(transport).me()
            XCTFail("expected DiscordError.decoding")
        } catch {
            XCTAssertEqual(error as? DiscordError, .decoding)
        }
    }

    // MARK: - 429 handling

    func testRateLimitSleepsRetryAfterThenRetriesOnce() async throws {
        var postCount = 0
        let transport = MockTransport { _ in
            postCount += 1
            if postCount == 1 {
                return (429, MockTransport.json(#"{"message": "You are being rate limited.", "retry_after": 1.5, "global": false}"#))
            }
            return (200, MockTransport.json("{}"))
        }
        let sleeper = SleepSpy()
        try await makeClient(transport, sleeper: sleeper).post(channelID: "7", content: "hi")

        XCTAssertEqual(sleeper.calls, [1.5])
        XCTAssertEqual(transport.log, ["POST /api/v10/channels/7/messages", "POST /api/v10/channels/7/messages"])
    }

    func testRateLimitTwiceGivesUpAfterOneRetry() async {
        let transport = MockTransport { _ in (429, MockTransport.json(#"{"retry_after": 0.25, "global": false}"#)) }
        let sleeper = SleepSpy()
        do {
            try await makeClient(transport, sleeper: sleeper).post(channelID: "7", content: "hi")
            XCTFail("expected DiscordError.http(429)")
        } catch {
            XCTAssertEqual(error as? DiscordError, .http(429))
        }
        XCTAssertEqual(sleeper.calls, [0.25])
        XCTAssertEqual(transport.requests.count, 2)
    }

    // MARK: - Broadcast

    func testForbiddenChannelFallsThroughToNextCandidate() async {
        let transport = MockTransport { request in
            switch request.url?.path ?? "" {
            case "/api/v10/users/@me/guilds": return (200, MockTransport.json(#"[{"id": "1", "name": "G"}]"#))
            case "/api/v10/guilds/1/channels": return (200, channelsJSON(["10", "11"]))
            case "/api/v10/channels/10/messages": return (403, forbiddenBody)
            case "/api/v10/channels/11/messages": return (200, okBody)
            default: return (404, okBody)
            }
        }
        let report = await makeClient(transport).broadcast("hello", channelCache: [:])

        XCTAssertEqual(report, DiscordPostReport(posted: ["1": "11"], failedGuilds: []))
        XCTAssertEqual(transport.log, [
            "GET /api/v10/users/@me/guilds",
            "GET /api/v10/guilds/1/channels",
            "POST /api/v10/channels/10/messages",
            "POST /api/v10/channels/11/messages",
        ])
    }

    func testGuildWhereEveryCandidateFailsIsReportedWhileOtherGuildPosts() async {
        let transport = MockTransport { request in
            switch request.url?.path ?? "" {
            case "/api/v10/users/@me/guilds":
                return (200, MockTransport.json(#"[{"id": "1", "name": "Locked"}, {"id": "2", "name": "Open"}]"#))
            case "/api/v10/guilds/1/channels":
                return (200, channelsJSON(["101", "102", "103", "104", "105", "106", "107"]))
            case "/api/v10/guilds/2/channels":
                return (200, channelsJSON(["201"]))
            case "/api/v10/channels/201/messages":
                return (200, okBody)
            default:
                return (403, forbiddenBody)
            }
        }
        let report = await makeClient(transport).broadcast("hello", channelCache: [:])

        XCTAssertEqual(report, DiscordPostReport(posted: ["2": "201"], failedGuilds: ["1"]))
        let guildOnePosts = transport.log.filter { $0.hasPrefix("POST /api/v10/channels/10") }
        XCTAssertEqual(guildOnePosts, [
            "POST /api/v10/channels/101/messages",
            "POST /api/v10/channels/102/messages",
            "POST /api/v10/channels/103/messages",
            "POST /api/v10/channels/104/messages",
            "POST /api/v10/channels/105/messages",
        ])
    }

    func testCachedChannelIsTriedFirst() async {
        let transport = MockTransport { request in
            switch request.url?.path ?? "" {
            case "/api/v10/users/@me/guilds":
                return (200, MockTransport.json(#"[{"id": "1", "name": "G"}]"#))
            case "/api/v10/guilds/1/channels":
                return (200, MockTransport.json("""
                [{"id": "10", "name": "general", "type": 0, "position": 0},
                 {"id": "12", "name": "lock-in", "type": 0, "position": 1},
                 {"id": "11", "name": "random", "type": 0, "position": 5}]
                """))
            default:
                return (200, MockTransport.json("{}"))
            }
        }
        let report = await makeClient(transport).broadcast("hello", channelCache: ["1": "11"])

        XCTAssertEqual(report.posted, ["1": "11"])
        XCTAssertEqual(transport.log.last, "POST /api/v10/channels/11/messages")
        XCTAssertEqual(transport.log.filter { $0.hasPrefix("POST") }.count, 1)
    }

    func testChannelListFailureMarksGuildFailed() async {
        let transport = MockTransport { request in
            if request.url?.path == "/api/v10/users/@me/guilds" {
                return (200, MockTransport.json(#"[{"id": "1", "name": "G"}]"#))
            }
            return (403, MockTransport.json("{}"))
        }
        let report = await makeClient(transport).broadcast("hello", channelCache: [:])

        XCTAssertEqual(report, DiscordPostReport(posted: [:], failedGuilds: ["1"]))
        XCTAssertEqual(transport.log, ["GET /api/v10/users/@me/guilds", "GET /api/v10/guilds/1/channels"])
    }

    func testGuildsFailureGivesEmptyReportAndStops() async {
        let transport = MockTransport { _ in (401, MockTransport.json(#"{"message": "401: Unauthorized"}"#)) }
        let report = await makeClient(transport).broadcast("hello", channelCache: ["1": "11"])

        XCTAssertEqual(report, DiscordPostReport())
        XCTAssertEqual(transport.log, ["GET /api/v10/users/@me/guilds"])
    }
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run from the repo root:

```bash
(cd Tofu && xcodegen generate && xcodebuild -project Tofu.xcodeproj -scheme Tofu -destination 'platform=macOS' test -only-testing:TofuTests/DiscordClientTests 2>&1 | tail -30)
```

Expected: the test target does not compile. The output contains `error: cannot find type 'HTTPTransport' in scope` (from `MockTransport.swift`) and ends with `** TEST FAILED **`.

- [ ] **Step 4: Implement DiscordClient**

Path segments are added with `URL.append(component:)` (macOS 13+). `@me` stays literal, and a `/` inside an id is percent-encoded, so an id can never add a path segment.

Create `Tofu/Tofu/Discord/DiscordClient.swift`:

```swift
import Foundation

/// Subset of a partial guild from `GET /users/@me/guilds`.
struct DiscordGuild: Decodable, Equatable {
    let id: String
    let name: String
}

/// Subset of the bot user from `GET /users/@me`.
struct DiscordUser: Decodable, Equatable {
    let id: String
    let username: String
}

enum DiscordError: Error, Equatable {
    /// Non-2xx status after at most one 429 retry.
    case http(Int)
    /// The request never produced an HTTP response (offline, DNS, TLS...).
    case transport(String)
    /// A 2xx body that did not decode, or a body that could not be encoded.
    case decoding
}

/// Seam between `DiscordClient` and the network so tests can script responses.
protocol HTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// Production transport backed by `URLSession.shared`.
struct URLSessionTransport: HTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DiscordError.transport("Response was not HTTP")
        }
        return (data, http)
    }
}

/// Outcome of `DiscordClient.broadcast`.
struct DiscordPostReport: Equatable {
    var posted: [String: String] = [:]   // guildID -> channelID
    var failedGuilds: [String] = []
}

/// Minimal Discord REST client for a bot token (spec §9).
final class DiscordClient {
    static let baseURL = URL(string: "https://discord.com/api/v10")!
    static let userAgent = "DiscordBot (tofu, 1.0)"
    /// Channels tried per guild before giving up on it.
    static let maxCandidatesPerGuild = 5
    /// Longest 429 wait we honor; a longer `retry_after` is clamped so a session end never hangs for minutes.
    static let maxRetryAfter: TimeInterval = 30

    private let token: String
    private let transport: HTTPTransport
    private let sleep: (TimeInterval) async -> Void

    init(token: String, transport: HTTPTransport = URLSessionTransport(),
         sleep: @escaping (TimeInterval) async -> Void = { seconds in
             try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
         }) {
        self.token = token
        self.transport = transport
        self.sleep = sleep
    }

    func me() async throws -> DiscordUser {
        try await get(["users", "@me"])
    }

    func guilds() async throws -> [DiscordGuild] {
        try await get(["users", "@me", "guilds"])
    }

    func channels(guildID: String) async throws -> [DiscordChannel] {
        try await get(["guilds", guildID, "channels"])
    }

    /// 429 -> sleep(retry_after) once and retry; other non-2xx -> DiscordError.http(code).
    func post(channelID: String, content: String) async throws {
        let message = OutgoingMessage(content: content, allowedMentions: .init(parse: []))
        let body: Data
        do {
            body = try JSONEncoder().encode(message)
        } catch {
            throw DiscordError.decoding
        }
        _ = try await send(method: "POST", path: ["channels", channelID, "messages"], body: body)
    }

    /// Every guild: try ChannelPicker candidates (max 5) until one succeeds. Never throws.
    func broadcast(_ content: String, channelCache: [String: String]) async -> DiscordPostReport {
        var report = DiscordPostReport()
        let allGuilds: [DiscordGuild]
        do {
            allGuilds = try await guilds()
        } catch {
            return report
        }
        for guild in allGuilds {
            if let channelID = await postToGuild(guild.id, content: content, cachedID: channelCache[guild.id]) {
                report.posted[guild.id] = channelID
            } else {
                report.failedGuilds.append(guild.id)
            }
        }
        return report
    }

    // MARK: - Private

    /// Returns the channel that accepted the message, or nil when every candidate failed.
    private func postToGuild(_ guildID: String, content: String, cachedID: String?) async -> String? {
        let guildChannels: [DiscordChannel]
        do {
            guildChannels = try await channels(guildID: guildID)
        } catch {
            return nil
        }
        let candidates = ChannelPicker.candidates(from: guildChannels, cachedID: cachedID)
        for channelID in candidates.prefix(Self.maxCandidatesPerGuild) {
            do {
                try await post(channelID: channelID, content: content)
                return channelID
            } catch {
                continue
            }
        }
        return nil
    }

    private func get<T: Decodable>(_ path: [String]) async throws -> T {
        let data = try await send(method: "GET", path: path, body: nil)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw DiscordError.decoding
        }
    }

    /// Sends once; on 429 sleeps `retry_after` and sends exactly one more time. Returns the 2xx body.
    private func send(method: String, path: [String], body: Data?) async throws -> Data {
        let request = makeRequest(method: method, path: path, body: body)
        var (data, response) = try await perform(request)
        if response.statusCode == 429 {
            await sleep(Self.retryAfter(body: data, response: response))
            (data, response) = try await perform(request)
        }
        guard (200..<300).contains(response.statusCode) else {
            throw DiscordError.http(response.statusCode)
        }
        return data
    }

    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            return try await transport.send(request)
        } catch let error as DiscordError {
            throw error
        } catch {
            throw DiscordError.transport(error.localizedDescription)
        }
    }

    /// Each path element is one URL component (a "/" inside an id is percent-encoded, never a new segment).
    private func makeRequest(method: String, path: [String], body: Data?) -> URLRequest {
        var url = Self.baseURL
        for component in path {
            url.append(component: component)
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bot \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        return request
    }

    /// `retry_after` (seconds, JSON body), else the Retry-After header, else 1 s; clamped to 0...maxRetryAfter.
    private static func retryAfter(body: Data, response: HTTPURLResponse) -> TimeInterval {
        let seconds: TimeInterval
        if let limit = try? JSONDecoder().decode(RateLimitBody.self, from: body) {
            seconds = limit.retryAfter
        } else if let header = response.value(forHTTPHeaderField: "Retry-After"), let value = TimeInterval(header) {
            seconds = value
        } else {
            seconds = 1
        }
        guard seconds.isFinite else { return maxRetryAfter }
        return min(max(0, seconds), maxRetryAfter)
    }
}

/// Body of `POST /channels/{id}/messages`. Empty `parse` disables every @mention ping.
private struct OutgoingMessage: Encodable {
    struct AllowedMentions: Encodable {
        let parse: [String]
    }

    let content: String
    let allowedMentions: AllowedMentions

    enum CodingKeys: String, CodingKey {
        case content
        case allowedMentions = "allowed_mentions"
    }
}

/// Body of a 429 response.
private struct RateLimitBody: Decodable {
    let retryAfter: TimeInterval

    enum CodingKeys: String, CodingKey {
        case retryAfter = "retry_after"
    }
}
```

- [ ] **Step 5: Run the DiscordClient tests to verify they pass**

Run from the repo root:

```bash
(cd Tofu && xcodegen generate && xcodebuild -project Tofu.xcodeproj -scheme Tofu -destination 'platform=macOS' test -only-testing:TofuTests/DiscordClientTests 2>&1 | tail -30)
```

Expected: all 12 `DiscordClientTests` cases pass, and the output ends with `** TEST SUCCEEDED **`. The run takes well under a second because `SleepSpy` never waits. A multi-second run means the default sleeping closure is in use by mistake.

- [ ] **Step 6: Run the full test suite**

Run from the repo root:

```bash
(cd Tofu && xcodegen generate && xcodebuild -project Tofu.xcodeproj -scheme Tofu -destination 'platform=macOS' test 2>&1 | tail -30)
```

Expected: `** TEST SUCCEEDED **`. Every test from Tasks 1–6 passes.

- [ ] **Step 7: Commit**

```bash
cd "$(git rev-parse --show-toplevel)" && git add Tofu/Tofu/Discord/DiscordClient.swift Tofu/TofuTests/MockTransport.swift Tofu/TofuTests/DiscordClientTests.swift Tofu/Tofu.xcodeproj
git commit -F - <<'EOF'
Add DiscordClient REST calls with 429 retry and per-guild fallback

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

### Task 7: App blocking (BlockPolicy, AttemptDebouncer, WorkspaceController, AppBlocker)

Lock-in hides every other app. During the session, any disallowed app that launches or comes to the front is hidden again at once and counted as an attempt. This task builds the pure rules (`BlockPolicy`, `AttemptDebouncer`) with TDD, then the two AppKit wrappers that apply them. Apps are only ever **hidden**, never quit. System Events and Accessibility are not used.

**Files:**
- Create: `Tofu/Tofu/System/BlockPolicy.swift`
- Create: `Tofu/Tofu/System/WorkspaceController.swift`
- Create: `Tofu/Tofu/System/AppBlocker.swift`
- Test: `Tofu/TofuTests/BlockPolicyTests.swift`
- Modify (regenerated by `xcodegen generate`): `Tofu/Tofu.xcodeproj`

**Interfaces:**
- Consumes (Task 2, `Models/Subject.swift`):
  ```swift
  struct AllowedApp: Codable, Hashable, Identifiable { var bundleID: String; var name: String }
  struct Subject: Codable, Identifiable, Hashable {
      var allowedApps: [AllowedApp]
      init(id: UUID = UUID(), name: String, preset: LayoutPreset = .split, sites: [String] = [],
           allowedApps: [AllowedApp] = [], extraDomains: [String] = [], createdAt: Date = Date())
  }
  ```
- Produces:
  ```swift
  struct RunningAppInfo: Equatable { let bundleID: String; let name: String; let isRegular: Bool }
  extension RunningAppInfo { init(_ app: NSRunningApplication) }          // extra helper (WorkspaceController.swift)
  enum BlockPolicy {
      static let alwaysAllowed: Set<String>                               // ["com.google.Chrome", "com.apple.finder"]
      static func allowedSet(for subject: Subject, ownBundleID: String) -> Set<String>
      static func shouldBlock(_ app: RunningAppInfo, allowed: Set<String>) -> Bool
  }
  struct AttemptDebouncer {
      var window: TimeInterval
      init(window: TimeInterval = 2)
      mutating func shouldCount(_ bundleID: String, at date: Date) -> Bool
  }
  @MainActor protocol WorkspaceControlling: AnyObject {
      func hideOthers(allowed: Set<String>) -> [String]
      func unhide(_ bundleIDs: [String])
      func activate(bundleID: String)
  }
  @MainActor final class WorkspaceController: WorkspaceControlling { init() }
  @MainActor protocol AppBlocking: AnyObject {
      var onBlocked: ((RunningAppInfo) -> Void)? { get set }
      func start(allowed: Set<String>)
      func stop()
  }
  @MainActor final class AppBlocker: AppBlocking {
      static let rehideDelays: [TimeInterval]                             // [0.3, 1.0] (extra)
      init(fallbackBundleID: String = "com.google.Chrome")
  }
  ```

- [ ] **Step 1: Write the failing test**

This covers Review Focus 1. Chrome, Finder and our own app are never blocked. `shouldBlock` has no state, so every repeated attempt is hidden. An attempt counts at most once per 2 s per app, and apps are debounced independently of each other.

Create `Tofu/TofuTests/BlockPolicyTests.swift`:

```swift
import XCTest
@testable import Tofu

final class BlockPolicyTests: XCTestCase {
    private let ownID = "com.tofu.app"
    private let t0 = Date(timeIntervalSince1970: 1_760_000_000)

    private func subject(apps: [AllowedApp] = []) -> Subject {
        Subject(name: "CS128", allowedApps: apps)
    }

    private func app(_ bundleID: String, regular: Bool = true) -> RunningAppInfo {
        RunningAppInfo(bundleID: bundleID, name: bundleID, isRegular: regular)
    }

    // MARK: allowedSet

    func testAllowedSetIsChromeFinderOwnAppAndSubjectApps() {
        let notes = AllowedApp(bundleID: "com.apple.Notes", name: "Notes")
        let allowed = BlockPolicy.allowedSet(for: subject(apps: [notes]), ownBundleID: ownID)
        XCTAssertEqual(allowed, ["com.google.Chrome", "com.apple.finder", ownID, "com.apple.Notes"])
    }

    func testAllowedSetWithoutSubjectAppsStillHasAlwaysAllowedAndOwnApp() {
        let allowed = BlockPolicy.allowedSet(for: subject(), ownBundleID: ownID)
        XCTAssertEqual(allowed, ["com.google.Chrome", "com.apple.finder", ownID])
    }

    // MARK: shouldBlock

    func testChromeFinderAndOwnAppAreNeverBlocked() {
        let allowed = BlockPolicy.allowedSet(for: subject(), ownBundleID: ownID)
        for id in ["com.google.Chrome", "com.apple.finder", ownID] {
            XCTAssertFalse(BlockPolicy.shouldBlock(app(id), allowed: allowed), id)
        }
    }

    func testSubjectAllowedAppIsNotBlocked() {
        let xcode = AllowedApp(bundleID: "com.apple.dt.Xcode", name: "Xcode")
        let allowed = BlockPolicy.allowedSet(for: subject(apps: [xcode]), ownBundleID: ownID)
        XCTAssertFalse(BlockPolicy.shouldBlock(app("com.apple.dt.Xcode"), allowed: allowed))
    }

    func testNonRegularAppIsNotBlocked() {
        let allowed = BlockPolicy.allowedSet(for: subject(), ownBundleID: ownID)
        XCTAssertFalse(BlockPolicy.shouldBlock(app("com.example.menubar", regular: false), allowed: allowed))
    }

    func testEmptyBundleIDIsNotBlocked() {
        let allowed = BlockPolicy.allowedSet(for: subject(), ownBundleID: ownID)
        XCTAssertFalse(BlockPolicy.shouldBlock(app(""), allowed: allowed))
    }

    func testDisallowedRegularAppIsBlocked() {
        let allowed = BlockPolicy.allowedSet(for: subject(), ownBundleID: ownID)
        XCTAssertTrue(BlockPolicy.shouldBlock(app("com.hnc.Discord"), allowed: allowed))
        XCTAssertTrue(BlockPolicy.shouldBlock(app("com.apple.Notes"), allowed: allowed))
    }

    func testShouldBlockIsStatelessSoEveryRepeatedAttemptIsHidden() {
        let allowed = BlockPolicy.allowedSet(for: subject(), ownBundleID: ownID)
        let discord = app("com.hnc.Discord")
        XCTAssertEqual((0..<5).map { _ in BlockPolicy.shouldBlock(discord, allowed: allowed) },
                       [true, true, true, true, true])
    }

    // MARK: AttemptDebouncer

    func testFirstAttemptCounts() {
        var debouncer = AttemptDebouncer()
        XCTAssertTrue(debouncer.shouldCount("com.hnc.Discord", at: t0))
    }

    func testRepeatWithinTwoSecondsDoesNotCount() {
        var debouncer = AttemptDebouncer()
        XCTAssertTrue(debouncer.shouldCount("com.hnc.Discord", at: t0))
        XCTAssertFalse(debouncer.shouldCount("com.hnc.Discord", at: t0))
        XCTAssertFalse(debouncer.shouldCount("com.hnc.Discord", at: t0.addingTimeInterval(0.5)))
        XCTAssertFalse(debouncer.shouldCount("com.hnc.Discord", at: t0.addingTimeInterval(1.99)))
    }

    func testRepeatAfterTwoSecondsCountsAgain() {
        var debouncer = AttemptDebouncer()
        XCTAssertTrue(debouncer.shouldCount("com.hnc.Discord", at: t0))
        XCTAssertTrue(debouncer.shouldCount("com.hnc.Discord", at: t0.addingTimeInterval(2)))
        XCTAssertFalse(debouncer.shouldCount("com.hnc.Discord", at: t0.addingTimeInterval(3)))
        XCTAssertTrue(debouncer.shouldCount("com.hnc.Discord", at: t0.addingTimeInterval(4.5)))
    }

    func testSuppressedAttemptsDoNotExtendTheWindow() {
        var debouncer = AttemptDebouncer()
        XCTAssertTrue(debouncer.shouldCount("com.hnc.Discord", at: t0))
        XCTAssertFalse(debouncer.shouldCount("com.hnc.Discord", at: t0.addingTimeInterval(1.5)))
        XCTAssertTrue(debouncer.shouldCount("com.hnc.Discord", at: t0.addingTimeInterval(2.1)))
    }

    func testDifferentAppsAreIndependent() {
        var debouncer = AttemptDebouncer()
        XCTAssertTrue(debouncer.shouldCount("com.hnc.Discord", at: t0))
        XCTAssertTrue(debouncer.shouldCount("com.apple.Notes", at: t0.addingTimeInterval(0.1)))
        XCTAssertFalse(debouncer.shouldCount("com.hnc.Discord", at: t0.addingTimeInterval(0.2)))
        XCTAssertFalse(debouncer.shouldCount("com.apple.Notes", at: t0.addingTimeInterval(0.3)))
    }

    func testCustomWindow() {
        var debouncer = AttemptDebouncer(window: 10)
        XCTAssertTrue(debouncer.shouldCount("com.hnc.Discord", at: t0))
        XCTAssertFalse(debouncer.shouldCount("com.hnc.Discord", at: t0.addingTimeInterval(9)))
        XCTAssertTrue(debouncer.shouldCount("com.hnc.Discord", at: t0.addingTimeInterval(10)))
    }
}
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `cd Tofu && xcodegen generate && xcodebuild -project Tofu.xcodeproj -scheme Tofu -destination 'platform=macOS' test -only-testing:TofuTests/BlockPolicyTests 2>&1 | tail -30`

Expected: the build fails with "cannot find" errors for the new types, such as `error: cannot find type 'RunningAppInfo' in scope` or `error: cannot find 'BlockPolicy' in scope` (which ones are listed depends on where the compiler stops), followed by `** TEST FAILED **`.

- [ ] **Step 3: Implement BlockPolicy, RunningAppInfo and AttemptDebouncer**

Create `Tofu/Tofu/System/BlockPolicy.swift`:

```swift
import Foundation

/// Snapshot of a running app, decoupled from `NSRunningApplication` so the rules stay testable.
struct RunningAppInfo: Equatable {
    let bundleID: String
    let name: String
    let isRegular: Bool
}

/// Pure rules for which apps may stay visible while locked in.
enum BlockPolicy {
    static let alwaysAllowed: Set<String> = ["com.google.Chrome", "com.apple.finder"]

    /// alwaysAllowed ∪ {ownBundleID} ∪ subject.allowedApps bundle IDs.
    static func allowedSet(for subject: Subject, ownBundleID: String) -> Set<String> {
        var allowed = alwaysAllowed
        allowed.insert(ownBundleID)
        allowed.formUnion(subject.allowedApps.map(\.bundleID))
        return allowed
    }

    /// isRegular && !allowed.contains(bundleID) && !bundleID.isEmpty
    static func shouldBlock(_ app: RunningAppInfo, allowed: Set<String>) -> Bool {
        app.isRegular && !app.bundleID.isEmpty && !allowed.contains(app.bundleID)
    }
}

/// Counts a blocked attempt at most once per `window` seconds per app
/// (a relaunch fires both "launched" and "activated" within milliseconds).
struct AttemptDebouncer {
    var window: TimeInterval
    private var lastCounted: [String: Date] = [:]

    init(window: TimeInterval = 2) { self.window = window }

    /// true if this bundleID was not counted within `window` seconds before `date`; records it when true.
    mutating func shouldCount(_ bundleID: String, at date: Date) -> Bool {
        if let last = lastCounted[bundleID], date.timeIntervalSince(last) < window {
            return false
        }
        lastCounted[bundleID] = date
        return true
    }
}
```

- [ ] **Step 4: Run the test and confirm it passes**

Run: `cd Tofu && xcodegen generate && xcodebuild -project Tofu.xcodeproj -scheme Tofu -destination 'platform=macOS' test -only-testing:TofuTests/BlockPolicyTests 2>&1 | tail -30`

Expected: `Executed 14 tests, with 0 failures` and `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
cd "$(git rev-parse --show-toplevel)" && git add Tofu/Tofu/System/BlockPolicy.swift Tofu/TofuTests/BlockPolicyTests.swift Tofu/Tofu.xcodeproj
git commit -F - <<'EOF'
Add BlockPolicy and AttemptDebouncer

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

- [ ] **Step 6: Write WorkspaceController**

`hideOthers` skips our own process (matched by PID) and apps that are already hidden. It reuses `BlockPolicy.shouldBlock`, so only `.regular` apps with a non-empty bundle ID outside `allowed` are hidden. It records a bundle ID only when `hide()` reports success. That way `unhide` later touches only apps we actually hid. `activate` uses the macOS 14 `NSRunningApplication.activate()`. It does not use the deprecated `activate(options: .activateIgnoringOtherApps)`.

Create `Tofu/Tofu/System/WorkspaceController.swift`:

```swift
import AppKit

@MainActor protocol WorkspaceControlling: AnyObject {
    /// Hides every running .regular app not in `allowed` and not already hidden. Returns bundle IDs hidden.
    func hideOthers(allowed: Set<String>) -> [String]
    /// Unhides running apps with these bundle IDs.
    func unhide(_ bundleIDs: [String])
    func activate(bundleID: String)
}

extension RunningAppInfo {
    /// Snapshot of a live app. A missing bundle ID becomes "" (never blocked); a missing name falls back to the bundle ID.
    init(_ app: NSRunningApplication) {
        let bundleID = app.bundleIdentifier ?? ""
        self.init(bundleID: bundleID,
                  name: app.localizedName ?? bundleID,
                  isRegular: app.activationPolicy == .regular)
    }
}

/// Hides and unhides other apps through NSWorkspace / NSRunningApplication. Never quits anything.
@MainActor final class WorkspaceController: WorkspaceControlling {
    init() {}

    func hideOthers(allowed: Set<String>) -> [String] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var hidden: [String] = []
        for app in NSWorkspace.shared.runningApplications {
            guard app.processIdentifier != ownPID, !app.isHidden else { continue }
            let info = RunningAppInfo(app)
            guard BlockPolicy.shouldBlock(info, allowed: allowed) else { continue }
            if app.hide(), !hidden.contains(info.bundleID) {
                hidden.append(info.bundleID)
            }
        }
        return hidden
    }

    func unhide(_ bundleIDs: [String]) {
        var seen = Set<String>()
        for bundleID in bundleIDs where seen.insert(bundleID).inserted {
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) where app.isHidden {
                app.unhide()
            }
        }
    }

    func activate(bundleID: String) {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.activate()
    }
}
```

- [ ] **Step 7: Write AppBlocker**

`AppBlocker` observes `NSWorkspace.shared.notificationCenter` for both `didLaunchApplicationNotification` and `didActivateApplicationNotification`, and reads the app from `userInfo[NSWorkspace.applicationUserInfoKey]`. The observer runs on `.main`, so it hops into the main actor with `MainActor.assumeIsolated` and passes only the PID, which is `Sendable`.

For a blocked app it does the following:
- calls `hide()`
- activates the fallback (Chrome) if it is running
- schedules re-hides at +0.3 s and +1.0 s, which only fire if the app is visible again (an app that is still launching can show its first window after our first `hide()`)
- calls `onBlocked` only when the debouncer counts the attempt

Each `start` and `stop` bumps a generation counter, so delayed re-hides from an earlier session do nothing.

Create `Tofu/Tofu/System/AppBlocker.swift`:

```swift
import AppKit

@MainActor protocol AppBlocking: AnyObject {
    /// Called once per counted attempt (after debounce). The app is hidden regardless.
    var onBlocked: ((RunningAppInfo) -> Void)? { get set }
    func start(allowed: Set<String>)
    func stop()
}

/// Hides disallowed apps the moment they launch or come to the front.
@MainActor final class AppBlocker: AppBlocking {
    /// Seconds after the first hide at which a still-visible app is hidden again
    /// (an app that is still launching can show itself again when its first window appears).
    static let rehideDelays: [TimeInterval] = [0.3, 1.0]

    var onBlocked: ((RunningAppInfo) -> Void)?
    private let fallbackBundleID: String
    private var allowed: Set<String> = []
    private var debouncer = AttemptDebouncer()
    private var observers: [NSObjectProtocol] = []
    /// Bumped by every start/stop so delayed re-hides from an earlier run do nothing.
    private var generation = 0

    /// After hiding, activates `fallbackBundleID` if it is running.
    init(fallbackBundleID: String = "com.google.Chrome") {
        self.fallbackBundleID = fallbackBundleID
    }

    func start(allowed: Set<String>) {
        stop()
        self.allowed = allowed
        debouncer = AttemptDebouncer()
        let center = NSWorkspace.shared.notificationCenter
        let names = [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didActivateApplicationNotification]
        for name in names {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                let pid = app.processIdentifier
                MainActor.assumeIsolated { self?.handle(pid: pid) }
            }
            observers.append(token)
        }
    }

    func stop() {
        let center = NSWorkspace.shared.notificationCenter
        for token in observers { center.removeObserver(token) }
        observers.removeAll()
        generation += 1
    }

    private func handle(pid: pid_t) {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return }
        let info = RunningAppInfo(app)
        guard BlockPolicy.shouldBlock(info, allowed: allowed) else { return }
        app.hide()
        activateFallback()
        scheduleRehides(pid: pid)
        if debouncer.shouldCount(info.bundleID, at: Date()) {
            onBlocked?(info)
        }
    }

    private func scheduleRehides(pid: pid_t) {
        let runGeneration = generation
        for delay in Self.rehideDelays {
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard let self, self.generation == runGeneration,
                      let app = NSRunningApplication(processIdentifier: pid), !app.isHidden else { return }
                app.hide()
                self.activateFallback()
            }
        }
    }

    private func activateFallback() {
        NSRunningApplication.runningApplications(withBundleIdentifier: fallbackBundleID).first?.activate()
    }
}
```

- [ ] **Step 8: Build**

Run: `cd Tofu && xcodegen generate && xcodebuild -project Tofu.xcodeproj -scheme Tofu -destination 'platform=macOS' build 2>&1 | tail -5`

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 9: Manual check of AppBlocker with a throwaway harness (nothing committed)**

The app does not use `AppBlocker` until Task 10/12. This harness compiles the real source files into a small command-line tool and runs the blocker for 45 s. Every app that is running right now stays allowed, except TextEdit, so nothing else gets hidden. At this point in the plan, `Models/`, `Engine/` and `System/` contain only Foundation/AppKit code, so they compile on their own.

Quit TextEdit first if it is open. Then run from the repo root:

```bash
mkdir -p /tmp/blocker-check
cat > /tmp/blocker-check/main.swift <<'EOF'
import AppKit

// Manual AppBlocker check: every app running right now stays allowed, except TextEdit.
MainActor.assumeIsolated {
    var allowed = BlockPolicy.alwaysAllowed
    for app in NSWorkspace.shared.runningApplications {
        if let bundleID = app.bundleIdentifier { allowed.insert(bundleID) }
    }
    allowed.remove("com.apple.TextEdit")

    let blocker = AppBlocker()
    blocker.onBlocked = { info in print("counted attempt: \(info.name) (\(info.bundleID))") }
    blocker.start(allowed: allowed)
    print("AppBlocker running for 45 s. Open TextEdit now.")
    RunLoop.main.run(until: Date().addingTimeInterval(45))
    blocker.stop()
    print("stopped")
}
EOF
xcrun swiftc -swift-version 5 -target "$(uname -m)-apple-macos14.0" \
  $(find Tofu/Tofu/Models Tofu/Tofu/Engine Tofu/Tofu/System -name '*.swift') \
  /tmp/blocker-check/main.swift -o /tmp/blocker-check/blocker-check
/tmp/blocker-check/blocker-check
```

Expected (do these while it is running):
1. Terminal prints `AppBlocker running for 45 s. Open TextEdit now.`
2. Open TextEdit with Spotlight. Its window or open panel flashes for well under a second and disappears. TextEdit is **still running** (its Dock icon keeps the running dot); it was hidden, not quit. Terminal prints exactly one line, `counted attempt: TextEdit (com.apple.TextEdit)`, even though both the launch and the activate notifications fired. If Chrome is running, it usually comes to the front. macOS 14 may decline that activation, and that is acceptable.
3. Click TextEdit's Dock icon three times quickly. It is hidden every time. At most one new `counted attempt` line appears per 2 s.
4. Wait 3 s and click the Dock icon once more. It is hidden, and exactly one new line appears.
5. After Terminal prints `stopped`, click TextEdit's Dock icon. It now shows normally because the blocker is off. Quit TextEdit (Cmd-Q).

- [ ] **Step 10: Run the full test suite**

Run: `cd Tofu && xcodegen generate && xcodebuild -project Tofu.xcodeproj -scheme Tofu -destination 'platform=macOS' test 2>&1 | tail -30`

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 11: Commit**

```bash
cd "$(git rev-parse --show-toplevel)" && git add Tofu/Tofu/System/WorkspaceController.swift Tofu/Tofu/System/AppBlocker.swift Tofu/Tofu.xcodeproj
git commit -F - <<'EOF'
Add WorkspaceController and AppBlocker (hide, re-hide, debounce)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 8: Chrome control (ChromeScripts, ChromeController)

Chrome is driven only through `NSAppleScript` and Chrome's own scripting dictionary. System Events and Accessibility are never used. `ChromeScripts` is pure: it builds the AppleScript text and parses its output, so it is unit-tested. `ChromeController` runs those scripts. It maps error −1743 to `.automationDenied`, and it unit-tests its script runner with plain AppleScript that never talks to Chrome.

Design notes (read before coding):
- **Window ids are text.** Chrome's dictionary declares a window's `id` as `text`. Scripts return ids as text, and Swift parses them to `Int`. When an id goes back into a script, it is quoted: `window id "123"`.
- **`tab` inside `tell application "Google Chrome"` means Chrome's *tab class*,** not the tab character. `listTabs` therefore captures `tab` and `linefeed` into variables *before* the tell block.
- **The user's own tabs are never closed.** `prepare` minimizes the user's existing windows, and they are restored at the end. Before opening the study windows, `prepare` records a snapshot of every existing tab as a "windowID<TAB>url" key. The tab watch skips those tabs. New tabs, and old tabs that navigate to a different URL, are still closed.
  - Without this, the first poll would close every off-topic tab in the user's minimized windows, and they would lose their tabs.
  - The spec says "every tab of every window". This is a deliberate refinement of that.
- **Never relaunch a quit Chrome.** Any `tell application "Google Chrome"` launches Chrome. So the tab poll and `restoreMinimized` do nothing while no Chrome process is running. Only `prepare` and `requestAccess` may launch Chrome.

**Files:**
- Create: `Tofu/Tofu/System/ChromeScripts.swift`
- Create: `Tofu/Tofu/System/ChromeController.swift`
- Test: `Tofu/TofuTests/ChromeScriptsTests.swift`
- Test: `Tofu/TofuTests/ChromeControllerTests.swift`
- Modify (regenerated by `xcodegen generate`): `Tofu/Tofu.xcodeproj`

**Interfaces:**
- Consumes:
  ```swift
  struct ChromeBounds: Equatable { var left: Int; var top: Int; var right: Int; var bottom: Int }   // Task 3
  enum DomainMatcher {                                                                              // Task 4
      static func normalizedURL(_ string: String) -> URL?
      static func host(of urlString: String) -> String?
      static func isAllowed(_ urlString: String, allowed: [String]) -> Bool
  }
  ```
- Produces:
  ```swift
  struct ChromeTab: Equatable { let windowID: Int; let tabIndex: Int; let url: String }   // tabIndex is 1-based
  enum ChromeError: Error, Equatable { case notInstalled, automationDenied, profileNotReady, scriptFailed(String) }
  enum ChromeScripts {
      static let bundleID = "com.google.Chrome"
      static func escape(_ s: String) -> String
      static func openWindow(url: String, bounds: ChromeBounds) -> String
      static func openWindow(url: String) -> String                                   // extra: no bounds line
      static let listTabs: String
      static func closeTab(windowID: Int, tabIndex: Int) -> String
      static let minimizeAll: String
      static func restore(windowIDs: [Int]) -> String
      static let ping: String
      static func parseTabs(_ output: String) -> [ChromeTab]
      static func parseIDs(_ output: String) -> [Int]
      static func protectionKey(_ tab: ChromeTab) -> String                           // extra
      static func tabsToClose(_ tabs: [ChromeTab], allowedDomains: [String],
                              protected: Set<String> = []) -> [ChromeTab]              // extra
  }
  @MainActor protocol ChromeControlling: AnyObject {
      var onTabClosed: ((String) -> Void)? { get set }
      func prepare(sites: [String], bounds: [ChromeBounds]) async -> ChromeError?
      func startTabWatch(allowedDomains: [String])
      func stopTabWatch()
      func restoreMinimized()
  }
  @MainActor final class ChromeController: ChromeControlling {
      static var isInstalled: Bool
      static var isRunning: Bool                                                      // extra
      static func run(_ source: String) -> Result<String, ChromeError>               // extra
      init()
      func requestAccess() -> ChromeError?
  }
  ```

- [ ] **Step 1: Write the failing ChromeScripts test**

Create `Tofu/TofuTests/ChromeScriptsTests.swift`:

```swift
import XCTest
@testable import Tofu

final class ChromeScriptsTests: XCTestCase {
    // MARK: escape

    func testEscapeQuotesAndBackslashes() {
        XCTAssertEqual(ChromeScripts.escape(#"a"b\c"#), #"a\"b\\c"#)
        XCTAssertEqual(ChromeScripts.escape("https://example.com/?q=1"), "https://example.com/?q=1")
    }

    // MARK: openWindow

    func testOpenWindowMakesWindowSetsEscapedURLAndBounds() {
        let script = ChromeScripts.openWindow(url: #"https://example.com/a"b"#,
                                              bounds: ChromeBounds(left: 0, top: 30, right: 840, bottom: 1050))
        XCTAssertTrue(script.contains("tell application \"Google Chrome\""))
        XCTAssertTrue(script.contains("make new window"))
        XCTAssertTrue(script.contains(#"set URL of active tab of w to "https://example.com/a\"b""#))
        XCTAssertTrue(script.contains("set bounds of w to {0, 30, 840, 1050}"))
        XCTAssertTrue(script.contains("return id of w as text"))
    }

    func testOpenWindowWithoutBoundsHasNoBoundsLine() {
        let script = ChromeScripts.openWindow(url: "https://piazza.com/class/x")
        XCTAssertTrue(script.contains("make new window"))
        XCTAssertTrue(script.contains(#"set URL of active tab of w to "https://piazza.com/class/x""#))
        XCTAssertFalse(script.contains("bounds"))
        XCTAssertTrue(script.contains("return id of w as text"))
    }

    // MARK: other scripts

    func testCloseTabTargetsTabIndexOfWindowID() {
        XCTAssertEqual(ChromeScripts.closeTab(windowID: 12, tabIndex: 3),
                       #"tell application "Google Chrome" to close tab 3 of window id "12""#)
    }

    func testRestoreUnminimizesEachIDInsideTry() {
        let script = ChromeScripts.restore(windowIDs: [5, 9])
        XCTAssertTrue(script.contains(#"set minimized of window id "5" to false"#))
        XCTAssertTrue(script.contains(#"set minimized of window id "9" to false"#))
        XCTAssertEqual(script.components(separatedBy: "try").count - 1, 4)   // 2 × "try" + 2 × "end try"
    }

    func testListTabsUsesTabAndLinefeedCapturedOutsideTell() {
        let script = ChromeScripts.listTabs
        XCTAssertTrue(script.hasPrefix("set tabChar to tab\nset lineChar to linefeed"))
        XCTAssertTrue(script.contains("URL of every tab of w"))
    }

    func testMinimizeAllAndPingTargetChrome() {
        XCTAssertTrue(ChromeScripts.minimizeAll.contains("set minimized of w to true"))
        XCTAssertTrue(ChromeScripts.minimizeAll.contains(#"set AppleScript's text item delimiters to ",""#))
        XCTAssertEqual(ChromeScripts.ping, #"tell application "Google Chrome" to count windows"#)
    }

    // MARK: parseTabs

    func testParseTabsMultipleLinesWithTrailingNewline() {
        let output = "101\t1\thttps://piazza.com/class/x\n101\t2\thttps://www.youtube.com/watch?v=1\n202\t1\tchrome://newtab/\n"
        XCTAssertEqual(ChromeScripts.parseTabs(output), [
            ChromeTab(windowID: 101, tabIndex: 1, url: "https://piazza.com/class/x"),
            ChromeTab(windowID: 101, tabIndex: 2, url: "https://www.youtube.com/watch?v=1"),
            ChromeTab(windowID: 202, tabIndex: 1, url: "chrome://newtab/"),
        ])
    }

    func testParseTabsSkipsMalformedLines() {
        let output = "garbage\n1\t2\nx\t1\thttps://a.com\n1\ty\thttps://b.com\n\n7\t3\thttps://ok.com\n"
        XCTAssertEqual(ChromeScripts.parseTabs(output), [ChromeTab(windowID: 7, tabIndex: 3, url: "https://ok.com")])
    }

    func testParseTabsKeepsURLWithSpacesAndHandlesCRLF() {
        let output = "3\t1\tfile:///Users/me/My Notes.pdf\r\n3\t2\thttps://a.com"
        XCTAssertEqual(ChromeScripts.parseTabs(output), [
            ChromeTab(windowID: 3, tabIndex: 1, url: "file:///Users/me/My Notes.pdf"),
            ChromeTab(windowID: 3, tabIndex: 2, url: "https://a.com"),
        ])
    }

    func testParseTabsEmptyOutput() {
        XCTAssertEqual(ChromeScripts.parseTabs(""), [])
    }

    // MARK: parseIDs

    func testParseIDs() {
        XCTAssertEqual(ChromeScripts.parseIDs(""), [])
        XCTAssertEqual(ChromeScripts.parseIDs("1,2, 3"), [1, 2, 3])
        XCTAssertEqual(ChromeScripts.parseIDs("junk"), [])
        XCTAssertEqual(ChromeScripts.parseIDs("4,junk,5\n"), [4, 5])
        XCTAssertEqual(ChromeScripts.parseIDs("1234567890"), [1_234_567_890])
    }

    // MARK: tabsToClose

    func testTabsToCloseKeepsAllowedAndBlankTabsAndOrdersDescendingPerWindow() {
        let tabs = [
            ChromeTab(windowID: 1, tabIndex: 1, url: "https://piazza.com/class/x"),
            ChromeTab(windowID: 1, tabIndex: 2, url: "https://reddit.com/r/all"),
            ChromeTab(windowID: 1, tabIndex: 3, url: "chrome://newtab/"),
            ChromeTab(windowID: 1, tabIndex: 4, url: "https://notyoutube.com/"),
            ChromeTab(windowID: 1, tabIndex: 5, url: "https://m.youtube.com/watch?v=1"),
            ChromeTab(windowID: 2, tabIndex: 1, url: "https://x.com/home"),
            ChromeTab(windowID: 2, tabIndex: 2, url: "about:blank"),
        ]
        let result = ChromeScripts.tabsToClose(tabs, allowedDomains: ["piazza.com", "youtube.com"])
        XCTAssertEqual(result, [
            ChromeTab(windowID: 1, tabIndex: 4, url: "https://notyoutube.com/"),
            ChromeTab(windowID: 1, tabIndex: 2, url: "https://reddit.com/r/all"),
            ChromeTab(windowID: 2, tabIndex: 1, url: "https://x.com/home"),
        ])
    }

    func testTabsToCloseIsEmptyWhenEverythingAllowed() {
        let tabs = [ChromeTab(windowID: 1, tabIndex: 1, url: "https://www.Piazza.com/class/x")]
        XCTAssertEqual(ChromeScripts.tabsToClose(tabs, allowedDomains: ["piazza.com"]), [])
    }

    func testProtectionKeyIsWindowAndURL() {
        XCTAssertEqual(ChromeScripts.protectionKey(ChromeTab(windowID: 9, tabIndex: 4, url: "https://a.com")),
                       "9\thttps://a.com")
    }

    func testPreexistingTabsAreProtectedButNewTabsInTheSameWindowAreNot() {
        let before = [ChromeTab(windowID: 9, tabIndex: 1, url: "https://youtube.com/watch?v=old")]
        let protected = Set(before.map(ChromeScripts.protectionKey))
        let now = [
            ChromeTab(windowID: 9, tabIndex: 1, url: "https://reddit.com/"),                 // new tab, shifted index
            ChromeTab(windowID: 9, tabIndex: 2, url: "https://youtube.com/watch?v=old"),     // pre-existing
            ChromeTab(windowID: 50, tabIndex: 1, url: "https://youtube.com/watch?v=old"),    // same URL, new window
        ]
        XCTAssertEqual(ChromeScripts.tabsToClose(now, allowedDomains: ["piazza.com"], protected: protected), [
            ChromeTab(windowID: 9, tabIndex: 1, url: "https://reddit.com/"),
            ChromeTab(windowID: 50, tabIndex: 1, url: "https://youtube.com/watch?v=old"),
        ])
    }
}
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `cd Tofu && xcodegen generate && xcodebuild -project Tofu.xcodeproj -scheme Tofu -destination 'platform=macOS' test -only-testing:TofuTests/ChromeScriptsTests 2>&1 | tail -30`

Expected: `error: cannot find 'ChromeScripts' in scope` (and `cannot find 'ChromeTab' in scope`), followed by `** TEST FAILED **`.

- [ ] **Step 3: Implement ChromeTab, ChromeError and ChromeScripts**

Create `Tofu/Tofu/System/ChromeScripts.swift`:

```swift
import Foundation

/// One Chrome tab as reported by `ChromeScripts.listTabs`.
struct ChromeTab: Equatable {
    let windowID: Int
    let tabIndex: Int   // 1-based AppleScript index
    let url: String
}

enum ChromeError: Error, Equatable {
    case notInstalled
    case automationDenied
    case profileNotReady
    case scriptFailed(String)
}

/// AppleScript source for Google Chrome plus parsers for the scripts' text output. Pure: nothing here runs a script.
/// Chrome declares window `id` as text, so window ids are quoted when they are put back into a script.
enum ChromeScripts {
    static let bundleID = "com.google.Chrome"

    /// Escapes backslash and double quote for embedding in an AppleScript string literal.
    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Makes a new window, sets active tab URL and bounds; returns the new window id as text.
    static func openWindow(url: String, bounds: ChromeBounds) -> String {
        openWindowScript(url: url, bounds: bounds)
    }

    /// Same as `openWindow(url:bounds:)` but leaves the window wherever Chrome puts it (no bounds line).
    static func openWindow(url: String) -> String {
        openWindowScript(url: url, bounds: nil)
    }

    private static func openWindowScript(url: String, bounds: ChromeBounds?) -> String {
        var lines = [
            "tell application \"Google Chrome\"",
            "    set w to make new window",
            "    set URL of active tab of w to \"\(escape(url))\"",
        ]
        if let b = bounds {
            lines.append("    set bounds of w to {\(b.left), \(b.top), \(b.right), \(b.bottom)}")
        }
        lines.append("    return id of w as text")
        lines.append("end tell")
        return lines.joined(separator: "\n")
    }

    /// Returns lines "windowID<TAB>tabIndex<TAB>url" separated by linefeed, for every tab of every window.
    /// `tab` and `linefeed` are captured before the tell block because inside it `tab` means Chrome's tab class.
    static let listTabs: String = """
        set tabChar to tab
        set lineChar to linefeed
        set out to ""
        tell application "Google Chrome"
            repeat with w in windows
                set wid to (id of w) as text
                set urls to URL of every tab of w
                repeat with i from 1 to count of urls
                    set out to out & wid & tabChar & (i as text) & tabChar & (item i of urls) & lineChar
                end repeat
            end repeat
        end tell
        return out
        """

    static func closeTab(windowID: Int, tabIndex: Int) -> String {
        "tell application \"Google Chrome\" to close tab \(tabIndex) of window id \"\(windowID)\""
    }

    /// Minimizes all non-minimized windows; returns their ids comma-separated ("" if none).
    static let minimizeAll: String = """
        set idList to {}
        tell application "Google Chrome"
            repeat with w in windows
                if minimized of w is false then
                    set minimized of w to true
                    set end of idList to ((id of w) as text)
                end if
            end repeat
        end tell
        set AppleScript's text item delimiters to ","
        set out to idList as text
        set AppleScript's text item delimiters to ""
        return out
        """

    /// Un-minimizes the given windows; ids that no longer exist are skipped by `try`.
    static func restore(windowIDs: [Int]) -> String {
        var lines = ["tell application \"Google Chrome\""]
        for id in windowIDs {
            lines.append("    try")
            lines.append("        set minimized of window id \"\(id)\" to false")
            lines.append("    end try")
        }
        lines.append("end tell")
        return lines.joined(separator: "\n")
    }

    /// Harmless call used to trigger/check the Automation permission: returns count of windows.
    static let ping: String = "tell application \"Google Chrome\" to count windows"

    /// Parses `listTabs` output. Lines that are not "Int<TAB>Int<TAB>url" are skipped; the URL keeps any spaces.
    static func parseTabs(_ output: String) -> [ChromeTab] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3,
                  let windowID = Int(parts[0].trimmingCharacters(in: .whitespaces)),
                  let tabIndex = Int(parts[1].trimmingCharacters(in: .whitespaces)) else { return nil }
            return ChromeTab(windowID: windowID, tabIndex: tabIndex, url: String(parts[2]))
        }
    }

    /// Parses `minimizeAll` / `openWindow` output: comma-separated integers; junk entries are dropped.
    static func parseIDs(_ output: String) -> [Int] {
        output.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    /// Identity of a tab that already existed before the session: "windowID<TAB>url" (index-independent).
    static func protectionKey(_ tab: ChromeTab) -> String {
        "\(tab.windowID)\t\(tab.url)"
    }

    /// Tabs to auto-close: URL not allowed and not `protected` (see `protectionKey`), ordered by window and then by
    /// descending tab index, so closing them one by one never shifts the index of a tab still to be closed.
    static func tabsToClose(_ tabs: [ChromeTab], allowedDomains: [String], protected: Set<String> = []) -> [ChromeTab] {
        tabs.filter { tab in
            !protected.contains(protectionKey(tab)) && !DomainMatcher.isAllowed(tab.url, allowed: allowedDomains)
        }
        .sorted { lhs, rhs in
            lhs.windowID != rhs.windowID ? lhs.windowID < rhs.windowID : lhs.tabIndex > rhs.tabIndex
        }
    }
}
```

- [ ] **Step 4: Run the test and confirm it passes**

Run: `cd Tofu && xcodegen generate && xcodebuild -project Tofu.xcodeproj -scheme Tofu -destination 'platform=macOS' test -only-testing:TofuTests/ChromeScriptsTests 2>&1 | tail -30`

Expected: `Executed 16 tests, with 0 failures` and `** TEST SUCCEEDED **`.

- [ ] **Step 5: Confirm every generated script compiles against Chrome's dictionary (osacompile; Chrome is not launched or controlled)**

`osacompile` only *compiles*. It reads Chrome's `scripting.sdef` from the app bundle and sends no Apple Events, so Chrome is not launched and no Automation prompt appears. Google Chrome must be installed, which the demo needs anyway. Run from the repo root:

```bash
mkdir -p /tmp/chrome-scripts
cat > /tmp/chrome-scripts/main.swift <<'EOF'
import Foundation

let dir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/chrome-scripts"
let scripts: [(String, String)] = [
    ("openWindow", ChromeScripts.openWindow(url: #"https://example.com/a"b\c"#,
                                            bounds: ChromeBounds(left: 0, top: 30, right: 840, bottom: 1050))),
    ("openWindowNoBounds", ChromeScripts.openWindow(url: "https://piazza.com/class/x")),
    ("listTabs", ChromeScripts.listTabs),
    ("closeTab", ChromeScripts.closeTab(windowID: 12, tabIndex: 3)),
    ("minimizeAll", ChromeScripts.minimizeAll),
    ("restore", ChromeScripts.restore(windowIDs: [5, 9])),
    ("restoreNone", ChromeScripts.restore(windowIDs: [])),
    ("ping", ChromeScripts.ping),
]
for (name, source) in scripts {
    let path = "\(dir)/\(name).applescript"
    do {
        try source.write(toFile: path, atomically: true, encoding: .utf8)
        print("wrote \(path)")
    } catch {
        print("could not write \(path): \(error)")
    }
}
EOF
xcrun swiftc -swift-version 5 -target "$(uname -m)-apple-macos14.0" \
  $(find Tofu/Tofu/Models Tofu/Tofu/Engine Tofu/Tofu/System -name '*.swift') \
  /tmp/chrome-scripts/main.swift -o /tmp/chrome-scripts/dump
/tmp/chrome-scripts/dump
for f in /tmp/chrome-scripts/*.applescript; do osacompile -o /tmp/chrome-scripts/x.scpt "$f" && echo "OK $(basename "$f")"; done
```

Expected: 8 `wrote /tmp/chrome-scripts/<name>.applescript` lines, then these 8 lines with no `syntax error` output:

```
OK closeTab.applescript
OK listTabs.applescript
OK minimizeAll.applescript
OK openWindow.applescript
OK openWindowNoBounds.applescript
OK ping.applescript
OK restore.applescript
OK restoreNone.applescript
```

You can also spot-check one script by hand: `osacompile -o /tmp/x.scpt -e 'tell application "Google Chrome" to count windows'` prints nothing and exits 0.

- [ ] **Step 6: Commit**

```bash
cd "$(git rev-parse --show-toplevel)" && git add Tofu/Tofu/System/ChromeScripts.swift Tofu/TofuTests/ChromeScriptsTests.swift Tofu/Tofu.xcodeproj
git commit -F - <<'EOF'
Add ChromeScripts AppleScript builders and output parsers

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

- [ ] **Step 7: Write the failing ChromeController runner test**

These tests run plain AppleScript (`return "hello"`, `error "Not authorized" number -1743`) through `ChromeController.run`. They never address Chrome or any other app, so they are safe in CI and trigger no permission prompt.

Create `Tofu/TofuTests/ChromeControllerTests.swift`:

```swift
import XCTest
@testable import Tofu

/// Exercises ChromeController.run with plain AppleScript that never talks to Chrome (or any other app).
@MainActor final class ChromeControllerTests: XCTestCase {
    func testRunReturnsTextResult() {
        XCTAssertEqual(ChromeController.run(#"return "hello""#), .success("hello"))
    }

    func testRunCoercesIntegerResultToText() {
        XCTAssertEqual(ChromeController.run("return 7"), .success("7"))
    }

    func testRunMapsErrorMinus1743ToAutomationDenied() {
        XCTAssertEqual(ChromeController.run(#"error "Not authorized" number -1743"#), .failure(.automationDenied))
    }

    func testRunMapsOtherErrorsToScriptFailedWithMessage() {
        XCTAssertEqual(ChromeController.run(#"error "boom" number 42"#), .failure(.scriptFailed("boom")))
    }

    func testRunReportsCompileErrorsAsScriptFailed() {
        guard case .failure(.scriptFailed(let message)) = ChromeController.run("set x to (") else {
            return XCTFail("expected .scriptFailed for a syntax error")
        }
        XCTAssertFalse(message.isEmpty)
    }
}
```

- [ ] **Step 8: Run the test and confirm it fails**

Run: `cd Tofu && xcodegen generate && xcodebuild -project Tofu.xcodeproj -scheme Tofu -destination 'platform=macOS' test -only-testing:TofuTests/ChromeControllerTests 2>&1 | tail -30`

Expected: `error: cannot find 'ChromeController' in scope`, followed by `** TEST FAILED **`.

- [ ] **Step 9: Implement ChromeControlling and ChromeController**

Behavior:
- `prepare` order:
  1. Return `.notInstalled` if `NSWorkspace.shared.urlForApplication(withBundleIdentifier:)` is nil.
  2. Launch or activate Chrome with `openApplication(at:configuration:)` (awaited), then wait up to 5 s for a running Chrome process.
  3. Run `minimizeAll` and store the ids. −1743 is fatal; other errors are not.
  4. Snapshot the existing tabs.
  5. For each site normalized with `DomainMatcher.normalizedURL` (nil is skipped), open a window, with `bounds[i]` when it exists. Each open is tried once and then retried up to 3× at 1 s intervals. −1743 returns `.automationDenied` immediately. Any other error that survives the retries returns `.profileNotReady`.
- The tab watch is a 2 s `Timer` on `RunLoop.main` in `.common` mode. Each tick does nothing unless Chrome is running. When it runs, it lists the tabs, closes the disallowed ones in descending index order per window, and calls `onTabClosed(host ?? url)` for each tab it closed.
- If permission is revoked mid-session (−1743), the watch stops.

Create `Tofu/Tofu/System/ChromeController.swift`:

```swift
import AppKit

@MainActor protocol ChromeControlling: AnyObject {
    /// Called with the closed tab's host (or URL if no host) after each auto-closed tab.
    var onTabClosed: ((String) -> Void)? { get set }
    /// Launch/activate Chrome, minimize existing windows, open one window per site (sites normalized with
    /// DomainMatcher.normalizedURL; unparseable sites skipped). bounds[i] applies to sites[i]; when bounds is
    /// shorter than sites (e.g. no screen), windows without a matching bounds entry are opened without setting bounds.
    /// Returns nil on success, otherwise the first fatal error (notInstalled / automationDenied / profileNotReady).
    func prepare(sites: [String], bounds: [ChromeBounds]) async -> ChromeError?
    func startTabWatch(allowedDomains: [String])
    func stopTabWatch()
    func restoreMinimized()
}

/// Drives Google Chrome with NSAppleScript (main thread). Never scripts System Events.
@MainActor final class ChromeController: ChromeControlling {
    /// AppleScript error number for "Not authorized to send Apple events" (Automation denied).
    static let automationDeniedErrorNumber = -1743
    static let tabPollInterval: TimeInterval = 2
    static let openRetries = 3
    static let launchTimeout: TimeInterval = 5

    var onTabClosed: ((String) -> Void)?
    private var minimizedIDs: [Int] = []
    /// Protection keys of the tabs that existed before `prepare` opened the study windows. The tab watch never
    /// closes them, so the user's own windows (minimized at lock-in, restored at the end) keep their tabs.
    private var preexistingTabs: Set<String> = []
    private var allowedDomains: [String] = []
    private var tabTimer: Timer?

    static var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: ChromeScripts.bundleID) != nil
    }

    /// True when a Chrome process exists. Scripts are only sent while this is true (except during prepare and
    /// requestAccess), because any `tell application "Google Chrome"` would relaunch a quit Chrome.
    static var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: ChromeScripts.bundleID).isEmpty
    }

    init() {}

    /// Compiles and runs `source`. Error -1743 maps to .automationDenied, every other error to .scriptFailed(message).
    static func run(_ source: String) -> Result<String, ChromeError> {
        guard let script = NSAppleScript(source: source) else {
            return .failure(.scriptFailed("Could not create AppleScript"))
        }
        var errorInfo: NSDictionary?
        let output = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let number = (errorInfo[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? 0
            if number == automationDeniedErrorNumber { return .failure(.automationDenied) }
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "AppleScript error \(number)"
            return .failure(.scriptFailed(message))
        }
        return .success(output.stringValue ?? "")
    }

    func prepare(sites: [String], bounds: [ChromeBounds]) async -> ChromeError? {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: ChromeScripts.bundleID) else {
            return .notInstalled
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        _ = try? await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
        var waited: TimeInterval = 0
        while !Self.isRunning && waited < Self.launchTimeout {
            try? await Task.sleep(nanoseconds: 100_000_000)
            waited += 0.1
        }

        switch Self.run(ChromeScripts.minimizeAll) {
        case .success(let output): minimizedIDs = ChromeScripts.parseIDs(output)
        case .failure(.automationDenied): return .automationDenied
        case .failure: minimizedIDs = []   // not fatal: the new windows still open on top
        }
        if case .success(let output) = Self.run(ChromeScripts.listTabs) {
            preexistingTabs = Set(ChromeScripts.parseTabs(output).map(ChromeScripts.protectionKey))
        } else {
            preexistingTabs = []
        }

        for (index, site) in sites.enumerated() {
            guard let url = DomainMatcher.normalizedURL(site) else { continue }
            let script = index < bounds.count
                ? ChromeScripts.openWindow(url: url.absoluteString, bounds: bounds[index])
                : ChromeScripts.openWindow(url: url.absoluteString)
            if let error = await openWithRetry(script) { return error }
        }
        return nil
    }

    /// First attempt plus `openRetries` retries, 1 s apart. `make new window` fails until a profile is loaded.
    private func openWithRetry(_ script: String) async -> ChromeError? {
        for attempt in 0...Self.openRetries {
            switch Self.run(script) {
            case .success: return nil
            case .failure(.automationDenied): return .automationDenied
            case .failure:
                if attempt < Self.openRetries { try? await Task.sleep(nanoseconds: 1_000_000_000) }
            }
        }
        return .profileNotReady
    }

    func startTabWatch(allowedDomains: [String]) {
        stopTabWatch()
        self.allowedDomains = allowedDomains
        let timer = Timer(timeInterval: Self.tabPollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollTabs() }
        }
        RunLoop.main.add(timer, forMode: .common)
        tabTimer = timer
    }

    func stopTabWatch() {
        tabTimer?.invalidate()
        tabTimer = nil
    }

    /// One poll: list every tab, close the disallowed ones (descending index per window), report each closed host.
    private func pollTabs() {
        guard Self.isRunning else { return }
        switch Self.run(ChromeScripts.listTabs) {
        case .success(let output):
            let tabs = ChromeScripts.parseTabs(output)
            for tab in ChromeScripts.tabsToClose(tabs, allowedDomains: allowedDomains, protected: preexistingTabs) {
                let script = ChromeScripts.closeTab(windowID: tab.windowID, tabIndex: tab.tabIndex)
                if case .success = Self.run(script) {
                    onTabClosed?(DomainMatcher.host(of: tab.url) ?? tab.url)
                }
            }
        case .failure(.automationDenied):
            stopTabWatch()   // permission revoked mid-session: stop retrying every 2 s
        case .failure:
            break            // Chrome busy or quitting; try again next tick
        }
    }

    func restoreMinimized() {
        let ids = minimizedIDs
        minimizedIDs = []
        guard !ids.isEmpty, Self.isRunning else { return }
        _ = Self.run(ChromeScripts.restore(windowIDs: ids))
    }

    /// Runs ChromeScripts.ping (launching Chrome if needed) to trigger the Automation prompt.
    func requestAccess() -> ChromeError? {
        guard Self.isInstalled else { return .notInstalled }
        switch Self.run(ChromeScripts.ping) {
        case .success: return nil
        case .failure(let error): return error
        }
    }
}
```

- [ ] **Step 10: Run the test and confirm it passes**

Run: `cd Tofu && xcodegen generate && xcodebuild -project Tofu.xcodeproj -scheme Tofu -destination 'platform=macOS' test -only-testing:TofuTests/ChromeControllerTests 2>&1 | tail -30`

Expected: `Executed 5 tests, with 0 failures` and `** TEST SUCCEEDED **`.

- [ ] **Step 11: Manual check against real Chrome with a throwaway harness (nothing committed)**

This step drives your real Chrome for about 45 s:
- Your existing Chrome windows are minimized and then restored.
- Their tabs are protected by the pre-existing-tab snapshot and are never closed.
- Two study windows open: example.com with bounds, and Wikipedia without bounds.

macOS attributes the Apple Events to your terminal app. The first run therefore shows "*Terminal* wants to control Google Chrome" (or iTerm, and so on); click **OK**. Run from the repo root:

```bash
mkdir -p /tmp/chrome-check
cat > /tmp/chrome-check/main.swift <<'EOF'
import AppKit

// Manual ChromeController check against the real Chrome. Existing windows are minimized, then restored.
MainActor.assumeIsolated {
    let chrome = ChromeController()
    chrome.onTabClosed = { host in print("closed tab: \(host)") }
    Task { @MainActor in
        let bounds = [ChromeBounds(left: 0, top: 40, right: 700, bottom: 800)]
        let error = await chrome.prepare(sites: ["Example.com", "en.wikipedia.org/wiki/Flow_(psychology)"],
                                         bounds: bounds)
        print("prepare -> \(error.map { "\($0)" } ?? "ok")")
        chrome.startTabWatch(allowedDomains: ["example.com", "wikipedia.org"])
        print("Tab watch is on for 40 s. Open youtube.com in a new tab (Cmd-T) of the example.com window.")
    }
    RunLoop.main.run(until: Date().addingTimeInterval(45))
    chrome.stopTabWatch()
    chrome.restoreMinimized()
    print("done")
}
EOF
xcrun swiftc -swift-version 5 -target "$(uname -m)-apple-macos14.0" \
  $(find Tofu/Tofu/Models Tofu/Tofu/Engine Tofu/Tofu/System -name '*.swift') \
  /tmp/chrome-check/main.swift -o /tmp/chrome-check/chrome-check
/tmp/chrome-check/chrome-check
```

Expected:
1. Chrome comes to the front. Every Chrome window that was already open minimizes into the Dock.
2. A window showing `https://example.com/` opens at the top-left. Its top edge is 40 pt below the top of the screen, and it is 700 pt wide and 760 pt tall. A second window shows the Wikipedia "Flow (psychology)" article wherever Chrome places it.
3. Terminal prints `prepare -> ok`.
   - If you clicked "Don't Allow" on the prompt, it prints `prepare -> automationDenied` instead. Re-enable access in System Settings › Privacy & Security › Automation › (your terminal) › Google Chrome, then rerun.
   - Right after a cold Chrome launch with the profile picker open, it prints `prepare -> profileNotReady` after about 3 s of retries. Pick a profile and rerun.
4. In the example.com window, press Cmd-T. The blank new tab stays open while you type. Go to `youtube.com`. Within about 2 s the tab closes and Terminal prints `closed tab: youtube.com`.
5. In the same window, open `https://en.wikipedia.org/wiki/Main_Page` in a new tab. It is **not** closed, because wikipedia.org is allowed.
6. After about 45 s Terminal prints `done`, and the windows that were minimized in (1) come back. The two study windows stay open; close them by hand.

- [ ] **Step 12: Run the full test suite**

Run: `cd Tofu && xcodegen generate && xcodebuild -project Tofu.xcodeproj -scheme Tofu -destination 'platform=macOS' test 2>&1 | tail -30`

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 13: Commit**

```bash
cd "$(git rev-parse --show-toplevel)" && git add Tofu/Tofu/System/ChromeController.swift Tofu/TofuTests/ChromeControllerTests.swift Tofu/Tofu.xcodeproj
git commit -F - <<'EOF'
Add ChromeController (launch, tile, retry, tab watch, restore)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 9: ToastCenter (top-right toast panels)

Toasts are black-and-white pills in the top-right corner of the main screen, below the menu bar, with a 16 pt margin. Each one is 320 × 56 pt and is inverted from the system appearance: black with white text in light mode, white with dark text in dark mode. Toasts are click-through, never take focus, show on every Space and over full-screen apps, and disappear after 3 s. At most 3 are visible; the newest is on top, and the oldest is dropped when a fourth arrives. The stacking math lives in the pure `ToastLayout`, which is unit-tested.

This task does **not** use `Theme`, which is only created in Task 13. The toast uses literal values: corner radius 10, horizontal padding 16.

**Files:**
- Create: `Tofu/Tofu/UI/ToastCenter.swift`
- Test: `Tofu/TofuTests/ToastLayoutTests.swift`
- Modify (regenerated by `xcodegen generate`): `Tofu/Tofu.xcodeproj`

**Interfaces:**
- Consumes (Task 3): `@MainActor static func ScreenGeometry.mainVisibleFrame() -> CGRect?`
- Produces:
  ```swift
  @MainActor protocol Toasting: AnyObject { func show(_ message: String) }
  enum ToastLayout {                                                       // extra, pure
      static let toastSize: CGSize        // 320 x 56
      static let gap: CGFloat             // 8
      static let margin: CGFloat          // 16
      static func frame(index: Int, size: CGSize, visible: CGRect, margin: CGFloat) -> CGRect
  }
  @MainActor final class ToastCenter: Toasting {
      static let shared: ToastCenter
      static let displayDuration: TimeInterval   // 3
      static let maxVisible: Int                 // 3
      init()
      func show(_ message: String)
  }
  struct ToastView: View { let message: String }
  ```

- [ ] **Step 1: Write the failing test**

Create `Tofu/TofuTests/ToastLayoutTests.swift`:

```swift
import XCTest
@testable import Tofu

final class ToastLayoutTests: XCTestCase {
    private let size = CGSize(width: 320, height: 56)
    private let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)

    func testToastSizeIs320Wide() {
        XCTAssertEqual(ToastLayout.toastSize, CGSize(width: 320, height: 56))
        XCTAssertEqual(ToastLayout.margin, 16)
        XCTAssertEqual(ToastLayout.gap, 8)
    }

    func testFirstToastSitsInTopRightCornerInsideMargin() {
        XCTAssertEqual(ToastLayout.frame(index: 0, size: size, visible: visible, margin: 16),
                       CGRect(x: 1104, y: 803, width: 320, height: 56))
    }

    func testEachNextToastStacksBelowWithEightPointGap() {
        XCTAssertEqual(ToastLayout.frame(index: 1, size: size, visible: visible, margin: 16),
                       CGRect(x: 1104, y: 739, width: 320, height: 56))
        XCTAssertEqual(ToastLayout.frame(index: 2, size: size, visible: visible, margin: 16),
                       CGRect(x: 1104, y: 675, width: 320, height: 56))
    }

    func testStackedToastsNeverOverlap() {
        for index in 0..<3 {
            let upper = ToastLayout.frame(index: index, size: size, visible: visible, margin: 16)
            let lower = ToastLayout.frame(index: index + 1, size: size, visible: visible, margin: 16)
            XCTAssertEqual(upper.minY - lower.maxY, 8)
        }
    }

    func testUsesVisibleFrameOriginForOffsetScreens() {
        let offset = CGRect(x: 100, y: 50, width: 800, height: 600)
        XCTAssertEqual(ToastLayout.frame(index: 0, size: size, visible: offset, margin: 16),
                       CGRect(x: 564, y: 578, width: 320, height: 56))
    }

    func testNegativeIndexIsTreatedAsTop() {
        XCTAssertEqual(ToastLayout.frame(index: -1, size: size, visible: visible, margin: 16),
                       ToastLayout.frame(index: 0, size: size, visible: visible, margin: 16))
    }
}
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `cd Tofu && xcodegen generate && xcodebuild -project Tofu.xcodeproj -scheme Tofu -destination 'platform=macOS' test -only-testing:TofuTests/ToastLayoutTests 2>&1 | tail -30`

Expected: `error: cannot find 'ToastLayout' in scope`, followed by `** TEST FAILED **`.

- [ ] **Step 3: Implement ToastLayout, ToastCenter and ToastView**

Panel settings that matter:
- `styleMask: [.borderless, .nonactivatingPanel]`, `level = .statusBar`, `ignoresMouseEvents = true`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`, and a clear background.
- `hidesOnDeactivate = false`. `NSPanel` hides itself whenever our app is not active, which is the normal state while locked in.
- `NSHostingView.sizingOptions = []`, so SwiftUI does not resize the panel.
- `orderFrontRegardless()`, because our app is usually in the background.

Create `Tofu/Tofu/UI/ToastCenter.swift`:

```swift
import AppKit
import SwiftUI

@MainActor protocol Toasting: AnyObject {
    func show(_ message: String)
}

/// Pure geometry for toasts stacked in the top-right corner of a screen's visible frame.
enum ToastLayout {
    static let toastSize = CGSize(width: 320, height: 56)
    static let gap: CGFloat = 8
    static let margin: CGFloat = 16

    /// Cocoa-coordinate frame of the toast at `index` (0 = top). Each next index sits `gap` points below the previous.
    static func frame(index: Int, size: CGSize, visible: CGRect, margin: CGFloat) -> CGRect {
        let row = CGFloat(max(0, index))
        let top = visible.maxY - margin - row * (size.height + gap)
        return CGRect(x: visible.maxX - margin - size.width, y: top - size.height,
                      width: size.width, height: size.height)
    }
}

/// Monochrome top-right toasts in borderless, non-activating, click-through panels.
/// Newest toast on top; at most `maxVisible` at once (the oldest is dropped); each disappears after `displayDuration`.
@MainActor final class ToastCenter: Toasting {
    static let shared = ToastCenter()
    static let displayDuration: TimeInterval = 3
    static let maxVisible = 3

    private struct Entry {
        let id: UUID
        let panel: NSPanel
    }

    /// Index 0 is the newest toast (drawn on top).
    private var entries: [Entry] = []

    init() {}

    func show(_ message: String) {
        guard let visible = ScreenGeometry.mainVisibleFrame() else { return }
        let entry = Entry(id: UUID(), panel: makePanel(message: message))
        entries.insert(entry, at: 0)
        while entries.count > Self.maxVisible {
            entries.removeLast().panel.orderOut(nil)
        }
        restack(in: visible)
        entry.panel.orderFrontRegardless()

        let id = entry.id
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.displayDuration * 1_000_000_000))
            self?.dismiss(id: id)
        }
    }

    private func dismiss(id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries.remove(at: index).panel.orderOut(nil)
        if let visible = ScreenGeometry.mainVisibleFrame() { restack(in: visible) }
    }

    private func restack(in visible: CGRect) {
        for (index, entry) in entries.enumerated() {
            let frame = ToastLayout.frame(index: index, size: ToastLayout.toastSize,
                                          visible: visible, margin: ToastLayout.margin)
            entry.panel.setFrame(frame, display: true)
        }
    }

    private func makePanel(message: String) -> NSPanel {
        let panel = NSPanel(contentRect: CGRect(origin: .zero, size: ToastLayout.toastSize),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false   // we are usually NOT the active app while locked in
        panel.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: ToastView(message: message))
        host.sizingOptions = []           // the panel keeps ToastLayout.toastSize
        host.frame = CGRect(origin: .zero, size: ToastLayout.toastSize)
        panel.contentView = host
        return panel
    }
}

/// Inverted pill: primary-colored fill (black in light mode, white in dark) with background-colored text.
struct ToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color(nsColor: .windowBackgroundColor))
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary))
    }
}
```

- [ ] **Step 4: Run the test and confirm it passes**

Run: `cd Tofu && xcodegen generate && xcodebuild -project Tofu.xcodeproj -scheme Tofu -destination 'platform=macOS' test -only-testing:TofuTests/ToastLayoutTests 2>&1 | tail -30`

Expected: `Executed 6 tests, with 0 failures` and `** TEST SUCCEEDED **`.

- [ ] **Step 5: Build and run the full test suite**

Run: `cd Tofu && xcodegen generate && xcodebuild -project Tofu.xcodeproj -scheme Tofu -destination 'platform=macOS' build 2>&1 | tail -5`

Expected: `** BUILD SUCCEEDED **`.

Run: `cd Tofu && xcodegen generate && xcodebuild -project Tofu.xcodeproj -scheme Tofu -destination 'platform=macOS' test 2>&1 | tail -30`

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Manual check is deferred to Task 14 (explicitly)**

Do not check toasts by hand now. Nothing shows a toast until `SessionEngine` (Task 10) and `AppModel` (Task 12) call `ToastCenter.shared.show(_:)`. **Task 14's end-to-end lock-in verification covers ToastCenter.** These are the observable expectations for that step:
- A toast appears in the top-right corner of the main screen, 16 pt below the menu bar and 16 pt from the right edge. It is 320 pt wide, black with white text in light mode and white with dark text in dark mode.
- It appears while Chrome (not our app) is frontmost and does not take focus. Clicks pass through it to the window underneath.
- It disappears after about 3 s.
- Trigger 4 toasts within 3 s, for example by opening 4 different blocked apps one after another. Repeats of the *same* app are debounced and show only one toast. At most 3 toasts are stacked at once, newest on top with 8 pt gaps, and the oldest is dropped.

- [ ] **Step 7: Commit**

```bash
cd "$(git rev-parse --show-toplevel)" && git add Tofu/Tofu/UI/ToastCenter.swift Tofu/TofuTests/ToastLayoutTests.swift Tofu/Tofu.xcodeproj
git commit -F - <<'EOF'
Add ToastCenter with pure ToastLayout stacking

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

### Task 10: SessionEngine

The lock-in state machine from spec §6, as `idle → locked → idle`. It drives every side effect through the protocols from Tasks 7–9, plus two new ones defined here: `Announcing` (Discord) and `WindowPresenting` (our own windows). Because of that, the whole lifecycle is unit-tested with fakes. This task also creates the shared test helper `Fakes.swift`, which Task 12 and later reuse.

Behavior notes. Each one is covered by the tests below:

- **`start`** does nothing while locked. In order, it:
  1. creates the session and reports it through `onSessionChanged`;
  2. hides every app outside `BlockPolicy.allowedSet`;
  3. computes Chrome bounds and the app zone from `LayoutEngine` and `ScreenGeometry` (if there is no screen: no bounds, and `appFrame` is nil);
  4. calls `presenter?.enterLocked(appFrame:)`;
  5. awaits `chrome.prepare`, toasting a mapped message on error;
  6. starts the blocker and the tab watch;
  7. starts the 1 s `Timer` (only when `startsTimers`);
  8. announces the start message.
- **Tab watch** is skipped after `.notInstalled` or `.automationDenied`, where every poll would fail (spec §12).
- **Quit during `prepare`:** if the session ended while `prepare` was suspended, `start` stops right after the `await`.
- **`tick()`** refreshes `now`. Every 30 s it updates `lastHeartbeat` and reports the session. When a goal is reached, it schedules exactly one `finish()`. An `isEnding` flag is set synchronously, and the task re-checks the session id before finishing.
- **`finish()`, `bail()` and `terminateNow()`** share `endSession(_:)`, which returns nil when idle, so every end runs at most once. Its steps:
  1. stop the timer, the blocker and the tab watch;
  2. stamp `end` and `lastHeartbeat`;
  3. unhide `hiddenByUs` and restore the minimized Chrome windows;
  4. clear the session and set `lastEnded`;
  5. report the final session.
- **`finish()` and `bail()`** then call `presenter?.exitLocked()`, show the toast `Saved: <duration> on <subject>`, and announce:
  - the ✅ message;
  - or the 🏳️ message, only for `.bailed` in goal mode.
- **`bail()`** in open mode, or after the goal has passed, ends as `.completed`.
- **`terminateNow()`** is synchronous. It ends as `.interrupted`, with no toast, no presenter call and no announcement.

**Files:**
- Create: `Tofu/Tofu/Engine/SessionEngine.swift`
- Create: `Tofu/TofuTests/Fakes.swift`
- Test: `Tofu/TofuTests/SessionEngineTests.swift`

**Interfaces:**
- Consumes:
  - Task 2: `struct Subject` (`id`, `name`, `preset`, `sites`, `allowedApps`, `extraDomains`); `enum SessionMode { case open; case goal(minutes: Int); var goalMinutes: Int?; var goalSeconds: TimeInterval? }`; `enum SessionOutcome: String, Codable { case completed, bailed, interrupted }`; `struct Session` with `init(id: UUID = UUID(), subjectID: UUID, subjectName: String, mode: SessionMode, start: Date, end: Date? = nil, lastHeartbeat: Date? = nil, blockedAttempts: Int = 0, closedTabs: Int = 0, outcome: SessionOutcome? = nil, isDemo: Bool = false)` and `var duration: TimeInterval`
  - Task 3: `static func LayoutEngine.layout(_ preset: LayoutPreset, in visible: CGRect) -> LayoutResult`; `struct LayoutResult { var chromeFrames: [CGRect]; var appFrame: CGRect? }`; `struct ChromeBounds: Equatable { var left: Int; var top: Int; var right: Int; var bottom: Int }`; `static func ScreenGeometry.chromeBounds(for rect: CGRect, primaryHeight: CGFloat) -> ChromeBounds`
  - Task 4: `static func DomainMatcher.allowedDomains(sites: [String], extra: [String]) -> [String]`
  - Task 5: `static func TimeFormat.short(_ seconds: TimeInterval) -> String`; `static func DiscordMessages.start(name: String, subject: String, mode: SessionMode) -> String`; `static func DiscordMessages.completed(name: String, subject: String, duration: TimeInterval, attempts: Int, tabs: Int) -> String`; `static func DiscordMessages.bailed(name: String, subject: String, duration: TimeInterval, goalMinutes: Int, attempts: Int) -> String`
  - Task 7: `static func BlockPolicy.allowedSet(for subject: Subject, ownBundleID: String) -> Set<String>`; `struct RunningAppInfo: Equatable { let bundleID: String; let name: String; let isRegular: Bool }`; `@MainActor protocol WorkspaceControlling: AnyObject { func hideOthers(allowed: Set<String>) -> [String]; func unhide(_ bundleIDs: [String]); func activate(bundleID: String) }`; `@MainActor protocol AppBlocking: AnyObject { var onBlocked: ((RunningAppInfo) -> Void)? { get set }; func start(allowed: Set<String>); func stop() }`
  - Task 8: `enum ChromeError: Error, Equatable { case notInstalled, automationDenied, profileNotReady, scriptFailed(String) }`; `@MainActor protocol ChromeControlling: AnyObject { var onTabClosed: ((String) -> Void)? { get set }; func prepare(sites: [String], bounds: [ChromeBounds]) async -> ChromeError?; func startTabWatch(allowedDomains: [String]); func stopTabWatch(); func restoreMinimized() }`
  - Task 9: `@MainActor protocol Toasting: AnyObject { func show(_ message: String) }`
- Produces:
  - `@MainActor protocol Announcing: AnyObject { func announce(_ content: String) }`
  - `@MainActor protocol WindowPresenting: AnyObject { func enterLocked(appFrame: CGRect?); func exitLocked() }`
  - `@Observable @MainActor final class SessionEngine` with:
    - `static let heartbeatInterval: TimeInterval = 30`
    - `private(set) var session: Session?`, `private(set) var subject: Subject?`, `private(set) var now: Date`, `private(set) var lastEnded: Session?`
    - `var isLocked: Bool`, `var elapsed: TimeInterval`, `var remaining: TimeInterval?`, `var goalReached: Bool`, `var needsGiveUpPhrase: Bool`
    - `weak var presenter: WindowPresenting?`, `var onSessionChanged: ((Session) -> Void)?`
    - `init(workspace: WorkspaceControlling, blocker: AppBlocking, chrome: ChromeControlling, toaster: Toasting, announcer: Announcing, ownBundleID: String, clock: @escaping () -> Date = Date.init, visibleFrame: @escaping () -> CGRect? = { nil }, primaryHeight: @escaping () -> CGFloat = { 0 }, startsTimers: Bool = true)`
    - `func start(subject: Subject, mode: SessionMode, displayName: String) async`
    - `func giveUpPhrase(template: String) -> String`, `func phraseMatches(_ typed: String, template: String) -> Bool`
    - `func finish() async`, `func bail() async`, `func tick()`, `func terminateNow()`
    - `static func chromeErrorMessage(_ error: ChromeError) -> String` (an addition beyond the binding interfaces)
  - Test helpers (`TofuTests/Fakes.swift`): `FakeWorkspace`, `FakeBlocker`, `FakeChrome`, `FakeToaster`, `FakeAnnouncer`, `FakePresenter`, `TestClock`, `EngineHarness` (fakes wired to an engine with `startsTimers: false`, a 1000×800 visible frame at the origin, and primary height 800)

- [ ] **Step 1: Create the shared fakes test helper**

Create `Tofu/TofuTests/Fakes.swift`:

```swift
// TofuTests/Fakes.swift — REAL CODE (created in Task 10, reused by Task 11+)
import AppKit
import Foundation
@testable import Tofu

@MainActor final class FakeWorkspace: WorkspaceControlling {
    var hideResult: [String] = []
    var hideCalls: [Set<String>] = []
    var unhideCalls: [[String]] = []
    var activated: [String] = []
    func hideOthers(allowed: Set<String>) -> [String] { hideCalls.append(allowed); return hideResult }
    func unhide(_ bundleIDs: [String]) { unhideCalls.append(bundleIDs) }
    func activate(bundleID: String) { activated.append(bundleID) }
}

@MainActor final class FakeBlocker: AppBlocking {
    var onBlocked: ((RunningAppInfo) -> Void)?
    var startedWith: Set<String>?
    var stopCount = 0
    func start(allowed: Set<String>) { startedWith = allowed }
    func stop() { stopCount += 1 }
    func simulateBlocked(_ bundleID: String, name: String = "App") {
        onBlocked?(RunningAppInfo(bundleID: bundleID, name: name, isRegular: true))
    }
}

@MainActor final class FakeChrome: ChromeControlling {
    var onTabClosed: ((String) -> Void)?
    var prepareResult: ChromeError?
    var preparedSites: [String] = []
    var preparedBounds: [ChromeBounds] = []
    var watchedDomains: [String]?
    var stopWatchCount = 0
    var restoreCount = 0
    func prepare(sites: [String], bounds: [ChromeBounds]) async -> ChromeError? {
        preparedSites = sites
        preparedBounds = bounds
        return prepareResult
    }
    func startTabWatch(allowedDomains: [String]) { watchedDomains = allowedDomains }
    func stopTabWatch() { stopWatchCount += 1 }
    func restoreMinimized() { restoreCount += 1 }
    func simulateTabClosed(_ host: String) { onTabClosed?(host) }
}

@MainActor final class FakeToaster: Toasting {
    var messages: [String] = []
    func show(_ message: String) { messages.append(message) }
}

@MainActor final class FakeAnnouncer: Announcing {
    var messages: [String] = []
    func announce(_ content: String) { messages.append(content) }
}

@MainActor final class FakePresenter: WindowPresenting {
    var entered: [CGRect?] = []
    var exitCount = 0
    func enterLocked(appFrame: CGRect?) { entered.append(appFrame) }
    func exitLocked() { exitCount += 1 }
}

final class TestClock {
    var now: Date
    init(_ now: Date = Date(timeIntervalSince1970: 1_760_000_000)) { self.now = now }
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

/// Bundle of fakes + an engine wired to them (startsTimers: false; screen 1000x800 at origin, primary height 800).
@MainActor struct EngineHarness {
    let workspace = FakeWorkspace()
    let blocker = FakeBlocker()
    let chrome = FakeChrome()
    let toaster = FakeToaster()
    let announcer = FakeAnnouncer()
    let presenter = FakePresenter()
    let clock = TestClock()
    let engine: SessionEngine

    init() {
        let clock = self.clock
        engine = SessionEngine(workspace: workspace, blocker: blocker, chrome: chrome, toaster: toaster,
                               announcer: announcer, ownBundleID: "com.tofu.app",
                               clock: { clock.now },
                               visibleFrame: { CGRect(x: 0, y: 0, width: 1000, height: 800) },
                               primaryHeight: { 800 }, startsTimers: false)
        engine.presenter = presenter
    }
}
```

- [ ] **Step 2: Write the failing SessionEngine tests**

Create `Tofu/TofuTests/SessionEngineTests.swift`. The cases map to Review Focus 3 (`testTerminateNowEndsInterruptedWithoutAnnouncing`) and Review Focus 4 (`testGoalCompletesExactlyOnceWhenCountdownReachesZero`, `testBailAfterGoalCountsAsCompleted`, `testGiveUpPhraseIgnoresCaseAndSurroundingWhitespace`). Expected geometry for the 1000×800 harness screen:

| Preset | Zones | Chrome bounds | App frame |
|---|---|---|---|
| split | 500 + 500 | `{0,0,500,800}`, `{500,0,1000,800}` | none (mini timer) |
| thirds | 333 + 333 + 334 | `{333,0,666,800}`, `{666,0,1000,800}` | `(0,0,333,800)` |
| mainSide | 700 + 300 | `{0,0,700,800}` | `(700,0,300,800)` |

```swift
import XCTest
@testable import Tofu

@MainActor
final class SessionEngineTests: XCTestCase {
    private let ownID = "com.tofu.app"
    private let template = "I give up on {subject}"

    /// CS128 with one extra allowed app and one extra domain; site count follows the preset.
    private func makeSubject(_ preset: LayoutPreset = .split) -> Subject {
        let sites = preset.siteCount == 2
            ? ["https://cs128.org/schedule", "https://docs.python.org/3/"]
            : ["https://cs128.org/schedule"]
        return Subject(name: "CS128", preset: preset, sites: sites,
                       allowedApps: [AllowedApp(bundleID: "com.microsoft.VSCode", name: "Visual Studio Code")],
                       extraDomains: ["piazza.com"])
    }

    /// Lets main-actor tasks spawned by the engine (the goal auto-finish) run.
    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }

    // MARK: Lock in

    func testStartHidesEverythingExceptAllowedApps() async {
        let h = EngineHarness()
        await h.engine.start(subject: makeSubject(), mode: .open, displayName: "Alex")

        XCTAssertEqual(h.workspace.hideCalls,
                       [[ownID, "com.google.Chrome", "com.apple.finder", "com.microsoft.VSCode"]])
        XCTAssertTrue(h.engine.isLocked)
        XCTAssertEqual(h.engine.subject?.name, "CS128")
        XCTAssertEqual(h.engine.session?.subjectName, "CS128")
        XCTAssertEqual(h.engine.session?.start, h.clock.now)
        XCTAssertNil(h.engine.session?.end)
        XCTAssertNil(h.engine.remaining)
        XCTAssertFalse(h.engine.needsGiveUpPhrase)
    }

    func testStartReportsNewSession() async {
        let h = EngineHarness()
        var changes: [Session] = []
        h.engine.onSessionChanged = { changes.append($0) }
        await h.engine.start(subject: makeSubject(), mode: .open, displayName: "Alex")

        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.first?.subjectName, "CS128")
        XCTAssertNil(changes.first?.end)
        XCTAssertEqual(changes.first?.id, h.engine.session?.id)
    }

    func testSplitPresetTilesTwoChromeHalvesAndShowsMiniTimer() async {
        let h = EngineHarness()
        let subject = makeSubject(.split)
        await h.engine.start(subject: subject, mode: .open, displayName: "Alex")

        XCTAssertEqual(h.chrome.preparedSites, subject.sites)
        XCTAssertEqual(h.chrome.preparedBounds, [ChromeBounds(left: 0, top: 0, right: 500, bottom: 800),
                                                 ChromeBounds(left: 500, top: 0, right: 1000, bottom: 800)])
        XCTAssertEqual(h.presenter.entered, [nil])
    }

    func testThirdsPresetGivesAppTheLeftThird() async {
        let h = EngineHarness()
        await h.engine.start(subject: makeSubject(.thirds), mode: .open, displayName: "Alex")

        XCTAssertEqual(h.presenter.entered, [CGRect(x: 0, y: 0, width: 333, height: 800)])
        XCTAssertEqual(h.chrome.preparedBounds, [ChromeBounds(left: 333, top: 0, right: 666, bottom: 800),
                                                 ChromeBounds(left: 666, top: 0, right: 1000, bottom: 800)])
    }

    func testMainSidePresetGivesAppTheRightThirty() async {
        let h = EngineHarness()
        await h.engine.start(subject: makeSubject(.mainSide), mode: .open, displayName: "Alex")

        XCTAssertEqual(h.presenter.entered, [CGRect(x: 700, y: 0, width: 300, height: 800)])
        XCTAssertEqual(h.chrome.preparedBounds, [ChromeBounds(left: 0, top: 0, right: 700, bottom: 800)])
    }

    func testWithoutScreenOpensSitesUntiledAndShowsMiniTimer() async {
        let chrome = FakeChrome()
        let presenter = FakePresenter()
        let engine = SessionEngine(workspace: FakeWorkspace(), blocker: FakeBlocker(), chrome: chrome,
                                   toaster: FakeToaster(), announcer: FakeAnnouncer(), ownBundleID: ownID,
                                   startsTimers: false)
        engine.presenter = presenter
        await engine.start(subject: makeSubject(.thirds), mode: .open, displayName: "Alex")

        XCTAssertEqual(chrome.preparedSites.count, 2)
        XCTAssertEqual(chrome.preparedBounds, [])
        XCTAssertEqual(presenter.entered, [nil])
        XCTAssertTrue(engine.isLocked)
    }

    func testStartBeginsBlockingAndTabWatchAndAnnounces() async {
        let h = EngineHarness()
        await h.engine.start(subject: makeSubject(), mode: .open, displayName: "Alex")

        XCTAssertEqual(h.blocker.startedWith, [ownID, "com.google.Chrome", "com.apple.finder", "com.microsoft.VSCode"])
        XCTAssertEqual(h.chrome.watchedDomains, ["cs128.org", "docs.python.org", "piazza.com"])
        XCTAssertEqual(h.announcer.messages, ["🔒 **Alex** is locked in on **CS128**"])
        XCTAssertEqual(h.toaster.messages, [])
    }

    func testGoalModeStartMessageIncludesGoal() async {
        let h = EngineHarness()
        await h.engine.start(subject: makeSubject(), mode: .goal(minutes: 25), displayName: "Alex")

        XCTAssertEqual(h.announcer.messages, ["🔒 **Alex** is locked in on **CS128** (goal 25m)"])
        XCTAssertEqual(h.engine.remaining, 1500)
        XCTAssertTrue(h.engine.needsGiveUpPhrase)
    }

    func testSecondStartIsIgnoredWhileLocked() async {
        let h = EngineHarness()
        await h.engine.start(subject: makeSubject(), mode: .open, displayName: "Alex")
        let other = Subject(name: "MATH241", preset: .full, sites: ["https://math.illinois.edu"])
        await h.engine.start(subject: other, mode: .goal(minutes: 25), displayName: "Alex")

        XCTAssertEqual(h.engine.session?.subjectName, "CS128")
        XCTAssertEqual(h.workspace.hideCalls.count, 1)
        XCTAssertEqual(h.presenter.entered.count, 1)
        XCTAssertEqual(h.announcer.messages.count, 1)
    }

    // MARK: Chrome failures

    func testChromeErrorsShowToastAndSessionContinues() async {
        let cases: [(ChromeError, String)] = [
            (.notInstalled, "Google Chrome not found — sites not opened"),
            (.automationDenied, "Allow Chrome control in System Settings › Privacy & Security › Automation"),
            (.profileNotReady, "Chrome wasn't ready — sites not opened"),
            (.scriptFailed("boom"), "Chrome error: boom"),
        ]
        for (error, expected) in cases {
            let h = EngineHarness()
            h.chrome.prepareResult = error
            await h.engine.start(subject: makeSubject(), mode: .open, displayName: "Alex")

            XCTAssertEqual(h.toaster.messages, [expected])
            XCTAssertTrue(h.engine.isLocked)
            XCTAssertNotNil(h.blocker.startedWith)
            XCTAssertEqual(h.announcer.messages.count, 1)
        }
    }

    func testTabWatchSkippedWhenChromeCannotBeScripted() async {
        let denied = EngineHarness()
        denied.chrome.prepareResult = .automationDenied
        await denied.engine.start(subject: makeSubject(), mode: .open, displayName: "Alex")
        XCTAssertNil(denied.chrome.watchedDomains)

        let missing = EngineHarness()
        missing.chrome.prepareResult = .notInstalled
        await missing.engine.start(subject: makeSubject(), mode: .open, displayName: "Alex")
        XCTAssertNil(missing.chrome.watchedDomains)

        let slow = EngineHarness()
        slow.chrome.prepareResult = .profileNotReady
        await slow.engine.start(subject: makeSubject(), mode: .open, displayName: "Alex")
        XCTAssertEqual(slow.chrome.watchedDomains, ["cs128.org", "docs.python.org", "piazza.com"])
    }

    // MARK: During the session

    func testBlockedAttemptCountsToastsAndPersists() async {
        let h = EngineHarness()
        await h.engine.start(subject: makeSubject(), mode: .open, displayName: "Alex")
        var changes: [Session] = []
        h.engine.onSessionChanged = { changes.append($0) }

        h.blocker.simulateBlocked("com.hnc.Discord", name: "Discord")

        XCTAssertEqual(h.engine.session?.blockedAttempts, 1)
        XCTAssertEqual(h.toaster.messages, ["🔒 Discord is blocked during CS128"])
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.last?.blockedAttempts, 1)
    }

    func testClosedTabCountsToastsAndPersists() async {
        let h = EngineHarness()
        await h.engine.start(subject: makeSubject(), mode: .open, displayName: "Alex")
        var changes: [Session] = []
        h.engine.onSessionChanged = { changes.append($0) }

        h.chrome.simulateTabClosed("youtube.com")

        XCTAssertEqual(h.engine.session?.closedTabs, 1)
        XCTAssertEqual(h.toaster.messages, ["Closed youtube.com — not part of CS128"])
        XCTAssertEqual(changes.last?.closedTabs, 1)
    }

    func testHeartbeatEvery30Seconds() async {
        let h = EngineHarness()
        await h.engine.start(subject: makeSubject(), mode: .open, displayName: "Alex")
        let start = h.clock.now
        var changes: [Session] = []
        h.engine.onSessionChanged = { changes.append($0) }

        h.clock.advance(29)
        h.engine.tick()
        XCTAssertEqual(h.engine.now, h.clock.now)
        XCTAssertEqual(h.engine.elapsed, 29, accuracy: 0.001)
        XCTAssertEqual(h.engine.session?.lastHeartbeat, start)
        XCTAssertTrue(changes.isEmpty)

        h.clock.advance(2)
        h.engine.tick()
        XCTAssertEqual(h.engine.elapsed, 31, accuracy: 0.001)
        XCTAssertEqual(h.engine.session?.lastHeartbeat, h.clock.now)
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.last?.lastHeartbeat, h.clock.now)
        XCTAssertNil(changes.last?.end)
    }

    // MARK: Goal countdown

    func testGoalCompletesExactlyOnceWhenCountdownReachesZero() async {
        let h = EngineHarness()
        await h.engine.start(subject: makeSubject(), mode: .goal(minutes: 1), displayName: "Alex")
        XCTAssertTrue(h.engine.needsGiveUpPhrase)
        XCTAssertEqual(h.engine.remaining, 60)

        h.clock.advance(30)
        h.engine.tick()
        XCTAssertEqual(h.engine.remaining, 30)
        XCTAssertTrue(h.engine.needsGiveUpPhrase)

        h.clock.advance(31)
        h.engine.tick()
        h.engine.tick()
        XCTAssertTrue(h.engine.goalReached)
        XCTAssertEqual(h.engine.remaining, 0)
        XCTAssertFalse(h.engine.needsGiveUpPhrase)

        await settle()
        XCTAssertFalse(h.engine.isLocked)
        XCTAssertEqual(h.engine.lastEnded?.outcome, .completed)
        XCTAssertEqual(h.engine.lastEnded?.end, h.clock.now)
        XCTAssertEqual(h.announcer.messages, [
            "🔒 **Alex** is locked in on **CS128** (goal 1m)",
            "✅ **Alex** locked in on **CS128** for **1m** · tried other apps **0×** · closed **0** tabs",
        ])
        XCTAssertEqual(h.toaster.messages, ["Saved: 1m on CS128"])
        XCTAssertEqual(h.presenter.exitCount, 1)
        XCTAssertEqual(h.blocker.stopCount, 1)

        // Late ticks and a late finish() change nothing.
        h.clock.advance(5)
        h.engine.tick()
        await h.engine.finish()
        await settle()
        XCTAssertEqual(h.announcer.messages.filter { $0.hasPrefix("✅") }.count, 1)
        XCTAssertEqual(h.announcer.messages.count, 2)
        XCTAssertEqual(h.workspace.unhideCalls.count, 1)
    }

    func testBailAfterGoalCountsAsCompleted() async {
        let h = EngineHarness()
        await h.engine.start(subject: makeSubject(), mode: .goal(minutes: 1), displayName: "Alex")
        h.clock.advance(61)

        await h.engine.bail()

        XCTAssertEqual(h.engine.lastEnded?.outcome, .completed)
        XCTAssertEqual(h.announcer.messages.last,
                       "✅ **Alex** locked in on **CS128** for **1m** · tried other apps **0×** · closed **0** tabs")
    }

    // MARK: Give-up phrase

    func testGiveUpPhraseIgnoresCaseAndSurroundingWhitespace() async {
        let h = EngineHarness()
        await h.engine.start(subject: makeSubject(), mode: .goal(minutes: 25), displayName: "Alex")

        XCTAssertEqual(h.engine.giveUpPhrase(template: template), "I give up on CS128")
        XCTAssertTrue(h.engine.phraseMatches("  i GIVE up on cs128 \n", template: template))
        XCTAssertTrue(h.engine.phraseMatches("I give up on CS128", template: template))
        XCTAssertFalse(h.engine.phraseMatches("I give up", template: template))
        XCTAssertFalse(h.engine.phraseMatches("I give up on CS12", template: template))
        XCTAssertFalse(h.engine.phraseMatches("", template: template))
    }

    // MARK: Ending

    func testBailInGoalModePostsBailedAndRestoresHiddenApps() async {
        let h = EngineHarness()
        h.workspace.hideResult = ["com.hnc.Discord"]
        await h.engine.start(subject: makeSubject(), mode: .goal(minutes: 25), displayName: "Alex")
        h.blocker.simulateBlocked("com.hnc.Discord", name: "Discord")
        h.clock.advance(600)

        await h.engine.bail()

        XCTAssertFalse(h.engine.isLocked)
        XCTAssertNil(h.engine.subject)
        XCTAssertEqual(h.engine.lastEnded?.outcome, .bailed)
        XCTAssertEqual(h.engine.lastEnded?.end, h.clock.now)
        XCTAssertEqual(h.engine.lastEnded?.blockedAttempts, 1)
        XCTAssertEqual(h.workspace.unhideCalls, [["com.hnc.Discord"]])
        XCTAssertEqual(h.chrome.restoreCount, 1)
        XCTAssertEqual(h.chrome.stopWatchCount, 1)
        XCTAssertEqual(h.blocker.stopCount, 1)
        XCTAssertEqual(h.presenter.exitCount, 1)
        XCTAssertEqual(h.toaster.messages.last, "Saved: 10m on CS128")
        XCTAssertEqual(h.announcer.messages.count, 2)
        XCTAssertEqual(h.announcer.messages.last,
                       DiscordMessages.bailed(name: "Alex", subject: "CS128", duration: 600,
                                              goalMinutes: 25, attempts: 1))
        XCTAssertTrue(h.announcer.messages.last?.hasPrefix("🏳️") ?? false)
    }

    func testFinishInOpenModePostsCompletedWithTotals() async {
        let h = EngineHarness()
        h.workspace.hideResult = ["com.apple.Notes"]
        var changes: [Session] = []
        h.engine.onSessionChanged = { changes.append($0) }
        await h.engine.start(subject: makeSubject(), mode: .open, displayName: "Alex")
        h.blocker.simulateBlocked("com.hnc.Discord", name: "Discord")
        h.blocker.simulateBlocked("com.apple.Notes", name: "Notes")
        h.chrome.simulateTabClosed("youtube.com")
        h.clock.advance(4800)

        await h.engine.finish()

        XCTAssertEqual(h.announcer.messages.last,
                       "✅ **Alex** locked in on **CS128** for **1h 20m** · tried other apps **2×** · closed **1** tabs")
        XCTAssertEqual(h.toaster.messages.last, "Saved: 1h 20m on CS128")
        XCTAssertEqual(h.workspace.unhideCalls, [["com.apple.Notes"]])
        XCTAssertEqual(changes.last?.outcome, .completed)
        XCTAssertEqual(changes.last?.end, h.clock.now)
        XCTAssertEqual(changes.last?.lastHeartbeat, h.clock.now)
        XCTAssertEqual(h.engine.lastEnded, changes.last)
        XCTAssertEqual(h.engine.lastEnded?.duration ?? 0, 4800, accuracy: 0.001)

        // Callbacks after the end are ignored.
        let toastCount = h.toaster.messages.count
        h.blocker.simulateBlocked("com.hnc.Discord", name: "Discord")
        XCTAssertEqual(h.toaster.messages.count, toastCount)
    }

    func testBailInOpenModeBehavesLikeFinish() async {
        let h = EngineHarness()
        await h.engine.start(subject: makeSubject(), mode: .open, displayName: "Alex")
        h.clock.advance(720)

        await h.engine.bail()

        XCTAssertEqual(h.engine.lastEnded?.outcome, .completed)
        XCTAssertEqual(h.announcer.messages.last,
                       "✅ **Alex** locked in on **CS128** for **12m** · tried other apps **0×** · closed **0** tabs")
    }

    func testTerminateNowEndsInterruptedWithoutAnnouncing() async {
        let h = EngineHarness()
        h.workspace.hideResult = ["com.hnc.Discord", "com.apple.Notes"]
        var changes: [Session] = []
        h.engine.onSessionChanged = { changes.append($0) }
        await h.engine.start(subject: makeSubject(), mode: .goal(minutes: 50), displayName: "Alex")
        h.clock.advance(120)

        h.engine.terminateNow()

        XCTAssertFalse(h.engine.isLocked)
        XCTAssertEqual(h.engine.lastEnded?.outcome, .interrupted)
        XCTAssertEqual(h.engine.lastEnded?.end, h.clock.now)
        XCTAssertEqual(changes.last?.outcome, .interrupted)
        XCTAssertEqual(h.workspace.unhideCalls, [["com.hnc.Discord", "com.apple.Notes"]])
        XCTAssertEqual(h.chrome.restoreCount, 1)
        XCTAssertEqual(h.chrome.stopWatchCount, 1)
        XCTAssertEqual(h.blocker.stopCount, 1)
        XCTAssertEqual(h.announcer.messages, ["🔒 **Alex** is locked in on **CS128** (goal 50m)"])

        // A later finish is a no-op: nothing is unhidden twice and nothing is posted.
        await h.engine.finish()
        XCTAssertEqual(h.announcer.messages.count, 1)
        XCTAssertEqual(h.workspace.unhideCalls.count, 1)
    }

    func testEndingWhileIdleDoesNothing() async {
        let h = EngineHarness()
        h.engine.terminateNow()
        await h.engine.finish()
        await h.engine.bail()
        h.engine.tick()

        XCTAssertNil(h.engine.lastEnded)
        XCTAssertTrue(h.workspace.unhideCalls.isEmpty)
        XCTAssertEqual(h.blocker.stopCount, 0)
        XCTAssertTrue(h.announcer.messages.isEmpty)
        XCTAssertEqual(h.engine.elapsed, 0)
    }
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run:

```bash
cd Tofu && xcodegen generate && xcodebuild -project Tofu.xcodeproj -scheme Tofu -destination 'platform=macOS' test -only-testing:TofuTests/SessionEngineTests 2>&1 | tail -30
```

Expected: the build fails, with errors including `error: cannot find type 'Announcing' in scope`, `error: cannot find type 'WindowPresenting' in scope` and `error: cannot find type 'SessionEngine' in scope` (from `Fakes.swift`), and then `** TEST FAILED **`.

- [ ] **Step 4: Implement SessionEngine**

Create `Tofu/Tofu/Engine/SessionEngine.swift`:

```swift
import AppKit
import Foundation
import Observation

/// Receives lock-in announcements (the live implementation posts to Discord).
@MainActor protocol Announcing: AnyObject {
    /// Fire-and-forget; must never block or throw.
    func announce(_ content: String)
}

/// Moves the app's own windows in and out of lock-in mode.
@MainActor protocol WindowPresenting: AnyObject {
    /// appFrame non-nil: put main window there and show LockedView. nil: hide main window, show mini timer.
    func enterLocked(appFrame: CGRect?)
    /// Close mini timer, restore main window frame, bring app to front.
    func exitLocked()
}

/// The lock-in state machine (spec §6): idle -> locked -> idle.
/// Orchestrates app hiding, Chrome tiling and tab watch, app blocking, the 1 s tick, the 30 s heartbeat
/// and announcements. Every side effect goes through an injected protocol so the engine is unit-testable.
@Observable @MainActor final class SessionEngine {
    static let heartbeatInterval: TimeInterval = 30

    private(set) var session: Session?
    private(set) var subject: Subject?
    private(set) var now: Date = Date()
    /// Most recently ended session (for the summary screen); nil until one ends.
    private(set) var lastEnded: Session?

    var isLocked: Bool { session != nil }

    /// Seconds since the session started, as of the last tick (0 when idle).
    var elapsed: TimeInterval {
        guard let session else { return 0 }
        return max(0, now.timeIntervalSince(session.start))
    }

    /// nil in open mode; clamped at 0.
    var remaining: TimeInterval? {
        guard let goal = session?.mode.goalSeconds else { return nil }
        return max(0, goal - elapsed)
    }

    /// Goal mode and the goal duration has elapsed.
    var goalReached: Bool {
        guard let goal = session?.mode.goalSeconds else { return false }
        return elapsed >= goal
    }

    /// Goal mode and goal not yet reached.
    var needsGiveUpPhrase: Bool {
        session?.mode.goalSeconds != nil && !goalReached
    }

    @ObservationIgnored weak var presenter: WindowPresenting?
    /// Called on create, every heartbeat, counter changes, and end. AppModel persists it.
    @ObservationIgnored var onSessionChanged: ((Session) -> Void)?

    private let workspace: WorkspaceControlling
    private let blocker: AppBlocking
    private let chrome: ChromeControlling
    private let toaster: Toasting
    private let announcer: Announcing
    private let ownBundleID: String
    private let clock: () -> Date
    private let visibleFrame: () -> CGRect?
    private let primaryHeight: () -> CGFloat
    private let startsTimers: Bool

    @ObservationIgnored private var displayName = ""
    /// Bundle IDs this session hid at lock-in; unhidden again at the end.
    @ObservationIgnored private var hiddenByUs: [String] = []
    @ObservationIgnored private var timer: Timer?
    /// Set synchronously when the goal auto-finish is scheduled so it is scheduled only once.
    @ObservationIgnored private var isEnding = false

    init(workspace: WorkspaceControlling, blocker: AppBlocking, chrome: ChromeControlling,
         toaster: Toasting, announcer: Announcing, ownBundleID: String,
         clock: @escaping () -> Date = Date.init,
         visibleFrame: @escaping () -> CGRect? = { nil },
         primaryHeight: @escaping () -> CGFloat = { 0 },
         startsTimers: Bool = true) {
        self.workspace = workspace
        self.blocker = blocker
        self.chrome = chrome
        self.toaster = toaster
        self.announcer = announcer
        self.ownBundleID = ownBundleID
        self.clock = clock
        self.visibleFrame = visibleFrame
        self.primaryHeight = primaryHeight
        self.startsTimers = startsTimers
        self.now = clock()
    }

    // MARK: Lock in

    /// Locks in on `subject` (spec §6 "Lock in"). Ignored while a session is already running.
    func start(subject: Subject, mode: SessionMode, displayName: String) async {
        guard !isLocked else { return }
        let startDate = clock()
        let newSession = Session(subjectID: subject.id, subjectName: subject.name, mode: mode, start: startDate)
        let sessionID = newSession.id
        now = startDate
        session = newSession
        self.subject = subject
        self.displayName = displayName
        isEnding = false
        onSessionChanged?(newSession)

        let allowed = BlockPolicy.allowedSet(for: subject, ownBundleID: ownBundleID)
        hiddenByUs = workspace.hideOthers(allowed: allowed)

        var bounds: [ChromeBounds] = []
        var appFrame: CGRect?
        if let visible = visibleFrame() {
            let layout = LayoutEngine.layout(subject.preset, in: visible)
            let height = primaryHeight()
            bounds = layout.chromeFrames.map { ScreenGeometry.chromeBounds(for: $0, primaryHeight: height) }
            appFrame = layout.appFrame
        }
        presenter?.enterLocked(appFrame: appFrame)

        let chromeError = await chrome.prepare(sites: subject.sites, bounds: bounds)
        // The session may have ended (e.g. the app quit) while Chrome was being prepared.
        guard session?.id == sessionID else { return }
        if let chromeError {
            toaster.show(Self.chromeErrorMessage(chromeError))
        }

        blocker.onBlocked = { [weak self] app in self?.recordBlocked(app) }
        blocker.start(allowed: allowed)

        chrome.onTabClosed = { [weak self] host in self?.recordClosedTab(host) }
        // Without Chrome (or without permission to script it) every poll would fail, so skip the watch.
        if chromeError != .notInstalled && chromeError != .automationDenied {
            chrome.startTabWatch(allowedDomains: DomainMatcher.allowedDomains(sites: subject.sites,
                                                                              extra: subject.extraDomains))
        }

        if startsTimers { startTimer() }
        announcer.announce(DiscordMessages.start(name: displayName, subject: subject.name, mode: mode))
    }

    /// Toast text for a Chrome failure during lock-in (spec §12).
    static func chromeErrorMessage(_ error: ChromeError) -> String {
        switch error {
        case .notInstalled:
            return "Google Chrome not found — sites not opened"
        case .automationDenied:
            return "Allow Chrome control in System Settings › Privacy & Security › Automation"
        case .profileNotReady:
            return "Chrome wasn't ready — sites not opened"
        case .scriptFailed(let message):
            return "Chrome error: \(message)"
        }
    }

    // MARK: Give-up phrase

    /// template with "{subject}" replaced by subject name.
    func giveUpPhrase(template: String) -> String {
        template.replacingOccurrences(of: "{subject}", with: subject?.name ?? "")
    }

    /// Case-insensitive, whitespace/newline-trimmed comparison.
    func phraseMatches(_ typed: String, template: String) -> Bool {
        let expected = giveUpPhrase(template: template).trimmingCharacters(in: .whitespacesAndNewlines)
        let actual = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        return !expected.isEmpty && actual.caseInsensitiveCompare(expected) == .orderedSame
    }

    // MARK: Running

    /// Updates `now` from clock, heartbeats, auto-finishes when goal reached.
    func tick() {
        now = clock()
        guard var current = session else { return }
        if now.timeIntervalSince(current.lastHeartbeat) >= Self.heartbeatInterval {
            current.lastHeartbeat = now
            session = current
            onSessionChanged?(current)
        }
        if goalReached && !isEnding {
            isEnding = true
            let sessionID = current.id
            Task { [weak self] in
                guard let self, self.session?.id == sessionID else { return }
                await self.finish()
            }
        }
    }

    private func startTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            // Scheduled on the main run loop, so this always fires on the main thread.
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func recordBlocked(_ app: RunningAppInfo) {
        guard var current = session else { return }
        current.blockedAttempts += 1
        session = current
        let name = app.name.isEmpty ? app.bundleID : app.name
        toaster.show("🔒 \(name) is blocked during \(current.subjectName)")
        onSessionChanged?(current)
    }

    private func recordClosedTab(_ host: String) {
        guard var current = session else { return }
        current.closedTabs += 1
        session = current
        toaster.show("Closed \(host) — not part of \(current.subjectName)")
        onSessionChanged?(current)
    }

    // MARK: End

    /// Ends as .completed (open mode, or goal reached). Posts completed message.
    func finish() async {
        finalize(.completed)
    }

    /// Ends as .bailed. Posts bailed message (goal mode) — in open mode behaves like finish().
    /// Once the goal has passed, a bail also counts as completed.
    func bail() async {
        guard isLocked else { return }
        now = clock()
        finalize(needsGiveUpPhrase ? .bailed : .completed)
    }

    /// Synchronous end for app termination: outcome .interrupted, unhide, restore Chrome, no Discord.
    func terminateNow() {
        _ = endSession(.interrupted)
    }

    /// Ends the session, then restores the UI, toasts the summary and announces it.
    private func finalize(_ outcome: SessionOutcome) {
        guard let final = endSession(outcome) else { return }
        presenter?.exitLocked()
        toaster.show("Saved: \(TimeFormat.short(final.duration)) on \(final.subjectName)")
        if outcome == .bailed, let goalMinutes = final.mode.goalMinutes {
            announcer.announce(DiscordMessages.bailed(name: displayName, subject: final.subjectName,
                                                      duration: final.duration, goalMinutes: goalMinutes,
                                                      attempts: final.blockedAttempts))
        } else {
            announcer.announce(DiscordMessages.completed(name: displayName, subject: final.subjectName,
                                                         duration: final.duration,
                                                         attempts: final.blockedAttempts,
                                                         tabs: final.closedTabs))
        }
    }

    /// Stops blocking and timers, stamps the end, unhides our hidden apps, restores Chrome windows and
    /// reports the final session. Returns nil when idle, so every end path runs at most once.
    private func endSession(_ outcome: SessionOutcome) -> Session? {
        guard var final = session else { return nil }
        timer?.invalidate()
        timer = nil
        blocker.stop()
        chrome.stopTabWatch()

        let endDate = clock()
        now = endDate
        final.end = endDate
        final.lastHeartbeat = endDate
        final.outcome = outcome

        workspace.unhide(hiddenByUs)
        hiddenByUs = []
        chrome.restoreMinimized()

        session = nil
        subject = nil
        isEnding = false
        lastEnded = final
        onSessionChanged?(final)
        return final
    }
}
```

- [ ] **Step 5: Run the SessionEngine tests to verify they pass**

Run:

```bash
cd Tofu && xcodegen generate && xcodebuild -project Tofu.xcodeproj -scheme Tofu -destination 'platform=macOS' test -only-testing:TofuTests/SessionEngineTests 2>&1 | tail -30
```

Expected: `Executed 22 tests, with 0 failures` and `** TEST SUCCEEDED **`.

- [ ] **Step 6: Run the full test suite**

Run:

```bash
cd Tofu && xcodegen generate && xcodebuild -project Tofu.xcodeproj -scheme Tofu -destination 'platform=macOS' test 2>&1 | tail -30
```

Expected: `** TEST SUCCEEDED **`. Every test class from Tasks 1–9 still passes alongside `SessionEngineTests`.

- [ ] **Step 7: Commit**

```bash
cd "$(git rev-parse --show-toplevel)" && git add Tofu/Tofu/Engine/SessionEngine.swift \
        Tofu/TofuTests/Fakes.swift \
        Tofu/TofuTests/SessionEngineTests.swift \
        Tofu/Tofu.xcodeproj
git commit -F - <<'EOF'
Add SessionEngine lock-in state machine with fake-driven tests

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

### Task 11: StatsEngine + DemoData

**Files:**
- Create: `Tofu/Tofu/Engine/StatsEngine.swift`
- Create: `Tofu/Tofu/Engine/DemoData.swift`
- Test: `Tofu/TofuTests/StatsEngineTests.swift`
- Test: `Tofu/TofuTests/DemoDataTests.swift`
- Modify (regenerated by `xcodegen generate`): `Tofu/Tofu.xcodeproj`

**Interfaces:**
- Consumes (Task 2, `Models/`):
  - `struct Session` — `subjectID: UUID`, `subjectName: String`, `mode: SessionMode`, `start: Date`, `end: Date?`, `lastHeartbeat: Date`, `blockedAttempts: Int`, `closedTabs: Int`, `outcome: SessionOutcome?`, `isDemo: Bool`, `var duration: TimeInterval`, and `init(id: UUID = UUID(), subjectID: UUID, subjectName: String, mode: SessionMode, start: Date, end: Date? = nil, lastHeartbeat: Date? = nil, blockedAttempts: Int = 0, closedTabs: Int = 0, outcome: SessionOutcome? = nil, isDemo: Bool = false)`
  - `enum SessionMode { case open; case goal(minutes: Int) }` with `var goalMinutes: Int?`
  - `enum SessionOutcome: String { case completed, bailed, interrupted }`
  - `struct Subject` with `init(id: UUID = UUID(), name: String, preset: LayoutPreset = .split, sites: [String] = [], allowedApps: [AllowedApp] = [], extraDomains: [String] = [], createdAt: Date = Date())`
  - `enum LayoutPreset` (`.split`, `.mainSide`, `var siteCount: Int`)
- Produces (Task 12 `AppModel.loadDemoData`, Task 16 `StatsView`/`SubjectStatsSection`):
  - `enum StatsRange: String, CaseIterable, Identifiable { case day, week, month; var id: String; var title: String }` — titles "Day", "Week", "Month"
  - `struct StatsBucket: Identifiable, Equatable { let start: Date; let label: String; let minutesBySubject: [String: Double]; var id: Date; var totalMinutes: Double }`
  - `struct StatsSummary: Equatable { var today: TimeInterval; var thisWeek: TimeInterval; var currentStreak: Int; var longestStreak: Int; var sessionCount: Int; var average: TimeInterval; var longest: TimeInterval; var blockedAttempts: Int; var closedTabs: Int; var bails: Int }`
  - `struct SubjectShare: Identifiable, Equatable { let name: String; let seconds: TimeInterval; let fraction: Double; var id: String }`
  - `struct StatsEngine { static let streakThreshold: TimeInterval = 300; static let otherLabel = "Other"; let calendar: Calendar; let now: Date; init(calendar: Calendar = .current, now: Date = Date()) }`
  - `func buckets(_ sessions: [Session], range: StatsRange, topSubjects: Int = 5) -> [StatsBucket]`
  - `func summary(_ sessions: [Session]) -> StatsSummary`
  - `func shares(_ sessions: [Session]) -> [SubjectShare]`
  - `enum DemoData { static func defaultSubjects(now: Date) -> [Subject]; static func generate(subjects: [Subject], days: Int = 30, now: Date, calendar: Calendar = .current, seed: UInt64 = 42) -> [Session] }`

Pure statistics for the Stats screen and subject detail cards (spec §10), plus seeded demo sessions. There are no AppKit dependencies, so everything here is unit-tested with a fixed calendar (Gregorian, UTC, `en_US_POSIX`, weeks start on Sunday) and a fixed `now` (Saturday 2026-10-10 15:00 UTC).

**Rules (spec §10) that the code and tests encode:**

- Sessions with `end == nil` (still active) are ignored by `buckets`, `summary` and `shares`.
- A session counts for the calendar day, week or month of its `start`. Sessions that cross midnight are not split.
- Time comes from `Session.duration`. An `interrupted` session has `end == lastHeartbeat` (set by `Store.finalizeInterrupted`), so it counts up to its last heartbeat.
- Buckets go oldest to newest:
  - `.day`: 14 buckets ending today. Each starts at `startOfDay`. Label format `"MMM d"`, e.g. "Oct 10".
  - `.week`: 12 buckets ending this week. Each starts at `calendar.dateInterval(of: .weekOfYear, for:)`, so the first weekday follows the calendar. Label `"MMM d"` of the week start, e.g. "Oct 4".
  - `.month`: 12 buckets ending this month. Label `"MMM"`, e.g. "Oct".
- Labels use a `DateFormatter` built from the calendar's locale and time zone.
- `minutesBySubject` holds `duration / 60` summed per `subjectName`. Subjects are ranked by total time across all given sessions. Those outside the top `topSubjects` are merged into `StatsEngine.otherLabel` ("Other").
- A streak day has at least `StatsEngine.streakThreshold` (300 s) in total.
  - `currentStreak` counts consecutive streak days ending today. If today is under the threshold, it counts back from yesterday.
  - `longestStreak` is the longest run of streak days anywhere in the data.
- `shares` are per `subjectName`, sorted by seconds descending (ties by name ascending). Each `fraction` is that subject's share of the total; it is 0 when the total is 0.
- `DemoData.generate` is seeded with SplitMix64 and is fully deterministic: the same inputs and seed give equal `[Session]`, ids included. Every session has `isDemo == true`, `end` set, `lastHeartbeat == end`, and `end <= now`.

- [ ] **Step 1: Write the failing StatsEngine tests**

Create `Tofu/TofuTests/StatsEngineTests.swift`:

```swift
import XCTest
@testable import Tofu

final class StatsEngineTests: XCTestCase {
    /// Gregorian, UTC, en_US_POSIX, weeks start on Sunday.
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = 1
        return calendar
    }()
    private let subjectID = UUID()

    /// Saturday 2026-10-10 15:00 UTC. This week starts Sunday 2026-10-04.
    private var now: Date { date(2026, 10, 10, 15) }
    private var engine: StatsEngine { StatsEngine(calendar: calendar, now: now) }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        guard let date = calendar.date(from: components) else { fatalError("invalid test date") }
        return date
    }

    /// Ended session of `minutes` length (end == lastHeartbeat).
    private func session(_ name: String, _ start: Date, minutes: Double, outcome: SessionOutcome = .completed,
                         attempts: Int = 0, tabs: Int = 0) -> Session {
        let end = start.addingTimeInterval(minutes * 60)
        return Session(subjectID: subjectID, subjectName: name, mode: .open, start: start, end: end,
                       lastHeartbeat: end, blockedAttempts: attempts, closedTabs: tabs, outcome: outcome)
    }

    // MARK: - Ranges

    func testRangeTitles() {
        XCTAssertEqual(StatsRange.allCases.map(\.title), ["Day", "Week", "Month"])
    }

    // MARK: - Buckets

    func testDayBucketsCoverFourteenDaysEndingToday() {
        let sessions = [
            session("CS128", date(2026, 10, 10, 9), minutes: 30),
            session("CS128", date(2026, 10, 10, 13), minutes: 15),
            session("MATH241", date(2026, 10, 9, 20), minutes: 60),
            session("CS128", date(2026, 9, 27, 8), minutes: 20),
            session("CS128", date(2026, 9, 26, 23), minutes: 50),   // 14 days ago: outside the range
        ]
        let buckets = engine.buckets(sessions, range: .day)

        XCTAssertEqual(buckets.count, 14)
        XCTAssertEqual(buckets.first?.start, date(2026, 9, 27, 0))
        XCTAssertEqual(buckets.first?.label, "Sep 27")
        XCTAssertEqual(buckets.last?.start, date(2026, 10, 10, 0))
        XCTAssertEqual(buckets.last?.label, "Oct 10")
        for (earlier, later) in zip(buckets, buckets.dropFirst()) {
            XCTAssertEqual(later.start.timeIntervalSince(earlier.start), 86_400)
        }
        XCTAssertEqual(buckets[13].minutesBySubject, ["CS128": 45])
        XCTAssertEqual(buckets[12].minutesBySubject, ["MATH241": 60])
        XCTAssertEqual(buckets[1].minutesBySubject, [:])
        XCTAssertEqual(buckets[0].minutesBySubject, ["CS128": 20])
        XCTAssertEqual(buckets.map(\.totalMinutes).reduce(0, +), 125)
    }

    func testSessionSpanningMidnightCountsOnItsStartDay() {
        let sessions = [session("CS128", date(2026, 10, 9, 23, 30), minutes: 60)]
        let buckets = engine.buckets(sessions, range: .day)

        XCTAssertEqual(buckets[12].minutesBySubject, ["CS128": 60])
        XCTAssertEqual(buckets[13].minutesBySubject, [:])
        XCTAssertEqual(engine.summary(sessions).today, 0)
    }

    func testWeekBucketsAreTwelveCalendarWeeksEndingThisWeek() {
        let sessions = [
            session("CS128", date(2026, 10, 4, 10), minutes: 40),    // Sunday: first day of this week
            session("CS128", date(2026, 10, 3, 10), minutes: 25),    // Saturday: previous week
            session("MATH241", date(2026, 7, 19, 10), minutes: 10),  // Sunday of the oldest week
            session("MATH241", date(2026, 7, 18, 10), minutes: 99),  // 12 weeks back: outside the range
        ]
        let buckets = engine.buckets(sessions, range: .week)

        XCTAssertEqual(buckets.count, 12)
        XCTAssertEqual(buckets.last?.start, date(2026, 10, 4, 0))
        XCTAssertEqual(buckets.last?.label, "Oct 4")
        XCTAssertEqual(buckets.first?.start, date(2026, 7, 19, 0))
        XCTAssertEqual(buckets.first?.label, "Jul 19")
        XCTAssertEqual(buckets[11].minutesBySubject, ["CS128": 40])
        XCTAssertEqual(buckets[10].minutesBySubject, ["CS128": 25])
        XCTAssertEqual(buckets[0].minutesBySubject, ["MATH241": 10])
        XCTAssertEqual(buckets.map(\.totalMinutes).reduce(0, +), 75)
    }

    func testMonthBucketsAreTwelveMonthsEndingThisMonth() {
        let sessions = [
            session("CS128", date(2026, 10, 1, 9), minutes: 30),
            session("CS128", date(2026, 9, 30, 9), minutes: 45),
            session("MATH241", date(2025, 11, 15, 9), minutes: 20),
            session("MATH241", date(2025, 10, 31, 9), minutes: 99),  // 12 months back: outside the range
        ]
        let buckets = engine.buckets(sessions, range: .month)

        XCTAssertEqual(buckets.count, 12)
        XCTAssertEqual(buckets.last?.start, date(2026, 10, 1, 0))
        XCTAssertEqual(buckets.last?.label, "Oct")
        XCTAssertEqual(buckets.first?.start, date(2025, 11, 1, 0))
        XCTAssertEqual(buckets.first?.label, "Nov")
        XCTAssertEqual(buckets[11].minutesBySubject, ["CS128": 30])
        XCTAssertEqual(buckets[10].minutesBySubject, ["CS128": 45])
        XCTAssertEqual(buckets[0].minutesBySubject, ["MATH241": 20])
        XCTAssertEqual(buckets.map(\.totalMinutes).reduce(0, +), 95)
    }

    func testActiveSessionIsIgnoredEverywhere() {
        let active = Session(subjectID: subjectID, subjectName: "CS128", mode: .open,
                             start: date(2026, 10, 10, 13), lastHeartbeat: date(2026, 10, 10, 14))
        let finished = session("CS128", date(2026, 10, 10, 9), minutes: 10)
        let sessions = [active, finished]

        XCTAssertEqual(engine.buckets(sessions, range: .day).last?.minutesBySubject, ["CS128": 10])
        let summary = engine.summary(sessions)
        XCTAssertEqual(summary.sessionCount, 1)
        XCTAssertEqual(summary.today, 600)
        XCTAssertEqual(engine.shares(sessions), [SubjectShare(name: "CS128", seconds: 600, fraction: 1)])
    }

    func testSubjectsOutsideTopNAreMergedIntoOther() {
        let sessions = [
            session("A", date(2026, 10, 10, 8), minutes: 100),
            session("B", date(2026, 10, 10, 10), minutes: 80),
            session("C", date(2026, 10, 10, 12), minutes: 60),
            session("D", date(2026, 10, 10, 14), minutes: 30),
            session("D", date(2026, 10, 1, 9), minutes: 200),   // makes D the biggest subject overall
        ]
        let top2 = engine.buckets(sessions, range: .day, topSubjects: 2)
        XCTAssertEqual(top2[13].minutesBySubject, ["D": 30, "A": 100, StatsEngine.otherLabel: 140])
        XCTAssertEqual(top2[4].minutesBySubject, ["D": 200])

        let defaultTop = engine.buckets(sessions, range: .day)
        XCTAssertEqual(defaultTop[13].minutesBySubject, ["A": 100, "B": 80, "C": 60, "D": 30])
    }

    // MARK: - Summary

    func testSummaryTodayAndThisWeek() {
        let sessions = [
            session("CS128", date(2026, 10, 10, 9), minutes: 30),
            session("MATH241", date(2026, 10, 10, 11), minutes: 15),
            session("CS128", date(2026, 10, 5, 9), minutes: 60),      // Monday of this week
            session("CS128", date(2026, 10, 4, 0, 30), minutes: 20),  // Sunday, first day of this week
            session("CS128", date(2026, 10, 3, 23), minutes: 90),     // Saturday of last week
        ]
        let summary = engine.summary(sessions)

        XCTAssertEqual(summary.today, 45 * 60)
        XCTAssertEqual(summary.thisWeek, 125 * 60)
        XCTAssertEqual(summary.sessionCount, 5)
    }

    func testCurrentStreakIncludesTodayWhenTodayQualifies() {
        let sessions = [
            session("CS128", date(2026, 10, 10, 9), minutes: 10),
            session("CS128", date(2026, 10, 9, 9), minutes: 10),
            session("CS128", date(2026, 10, 8, 9), minutes: 10),
            session("CS128", date(2026, 10, 6, 9), minutes: 10),   // Oct 7 is missing
        ]
        let summary = engine.summary(sessions)

        XCTAssertEqual(summary.currentStreak, 3)
        XCTAssertEqual(summary.longestStreak, 3)
    }

    func testCurrentStreakCountsFromYesterdayWhenTodayIsUnderFiveMinutes() {
        let sessions = [
            session("CS128", date(2026, 10, 10, 9), minutes: 4),    // today: below the threshold
            session("CS128", date(2026, 10, 9, 9), minutes: 30),
            session("CS128", date(2026, 10, 8, 9), minutes: 30),
            session("CS128", date(2026, 10, 7, 9), minutes: 3),     // two short sessions add up to 6 min
            session("MATH241", date(2026, 10, 7, 18), minutes: 3),
        ]

        XCTAssertEqual(engine.summary(sessions).currentStreak, 3)
    }

    func testExactlyFiveMinutesQualifies() {
        let sessions = [
            session("CS128", date(2026, 10, 10, 9), minutes: 5),
            session("CS128", date(2026, 10, 9, 9), minutes: 5),
        ]

        XCTAssertEqual(engine.summary(sessions).currentStreak, 2)
    }

    func testGapBreaksCurrentStreak() {
        let sessions = [
            session("CS128", date(2026, 10, 10, 9), minutes: 10),
            session("CS128", date(2026, 10, 8, 9), minutes: 10),   // Oct 9 is missing
            session("CS128", date(2026, 10, 7, 9), minutes: 10),
        ]
        let summary = engine.summary(sessions)

        XCTAssertEqual(summary.currentStreak, 1)
        XCTAssertEqual(summary.longestStreak, 2)
    }

    func testNoCurrentStreakWhenTodayAndYesterdayAreEmpty() {
        let sessions = [
            session("CS128", date(2026, 10, 8, 9), minutes: 10),
            session("CS128", date(2026, 10, 7, 9), minutes: 10),
        ]
        let summary = engine.summary(sessions)

        XCTAssertEqual(summary.currentStreak, 0)
        XCTAssertEqual(summary.longestStreak, 2)
    }

    func testLongestStreakFindsLongestRunOfQualifyingDays() {
        var sessions = (1...5).map { session("CS128", date(2026, 9, $0, 9), minutes: 10) }   // Sep 1-5
        sessions += [
            session("CS128", date(2026, 9, 20, 9), minutes: 10),
            session("CS128", date(2026, 9, 21, 9), minutes: 4),    // too short: breaks Sep 20-22
            session("CS128", date(2026, 9, 22, 9), minutes: 10),
            session("CS128", date(2026, 10, 9, 9), minutes: 10),
            session("CS128", date(2026, 10, 10, 9), minutes: 10),
        ]
        let summary = engine.summary(sessions)

        XCTAssertEqual(summary.longestStreak, 5)
        XCTAssertEqual(summary.currentStreak, 2)
    }

    func testAverageAndLongestSession() {
        let sessions = [
            session("CS128", date(2026, 10, 8, 9), minutes: 10),
            session("CS128", date(2026, 10, 9, 9), minutes: 20),
            session("MATH241", date(2026, 10, 10, 9), minutes: 60),
        ]
        let summary = engine.summary(sessions)

        XCTAssertEqual(summary.sessionCount, 3)
        XCTAssertEqual(summary.average, 30 * 60, accuracy: 0.001)
        XCTAssertEqual(summary.longest, 60 * 60)
    }

    func testEmptySummaryIsAllZero() {
        let expected = StatsSummary(today: 0, thisWeek: 0, currentStreak: 0, longestStreak: 0, sessionCount: 0,
                                    average: 0, longest: 0, blockedAttempts: 0, closedTabs: 0, bails: 0)
        XCTAssertEqual(engine.summary([]), expected)
    }

    func testBailsAttemptsAndClosedTabsAreTotalled() {
        let sessions = [
            session("CS128", date(2026, 10, 7, 9), minutes: 10, outcome: .completed, attempts: 1, tabs: 0),
            session("CS128", date(2026, 10, 8, 9), minutes: 10, outcome: .bailed, attempts: 2, tabs: 1),
            session("CS128", date(2026, 10, 9, 9), minutes: 10, outcome: .bailed, attempts: 3, tabs: 4),
            session("CS128", date(2026, 10, 10, 9), minutes: 10, outcome: .interrupted, attempts: 0, tabs: 2),
        ]
        let summary = engine.summary(sessions)

        XCTAssertEqual(summary.bails, 2)
        XCTAssertEqual(summary.blockedAttempts, 6)
        XCTAssertEqual(summary.closedTabs, 7)
    }

    func testInterruptedSessionCountsUpToItsLastHeartbeat() {
        let start = date(2026, 10, 10, 9)
        let heartbeat = date(2026, 10, 10, 9, 40)
        // Store.finalizeInterrupted sets end = lastHeartbeat after a crash.
        let interrupted = Session(subjectID: subjectID, subjectName: "CS128", mode: .goal(minutes: 50),
                                  start: start, end: heartbeat, lastHeartbeat: heartbeat, outcome: .interrupted)
        let summary = engine.summary([interrupted])

        XCTAssertEqual(summary.today, 40 * 60)
        XCTAssertEqual(summary.sessionCount, 1)
        XCTAssertEqual(summary.bails, 0)
        XCTAssertEqual(engine.buckets([interrupted], range: .day).last?.minutesBySubject, ["CS128": 40])
    }

    // MARK: - Shares

    func testSharesAreSortedDescendingAndSumToOne() {
        let active = Session(subjectID: subjectID, subjectName: "D", mode: .open,
                             start: date(2026, 10, 10, 13), lastHeartbeat: date(2026, 10, 10, 14))
        let sessions = [
            session("A", date(2026, 10, 8, 9), minutes: 30),
            session("B", date(2026, 10, 9, 9), minutes: 90),
            session("C", date(2026, 10, 10, 9), minutes: 60),
            active,
        ]
        let shares = engine.shares(sessions)

        XCTAssertEqual(shares.map(\.name), ["B", "C", "A"])
        XCTAssertEqual(shares.map(\.seconds), [5400, 3600, 1800])
        XCTAssertEqual(shares[0].fraction, 0.5, accuracy: 1e-9)
        XCTAssertEqual(shares[1].fraction, 1.0 / 3.0, accuracy: 1e-9)
        XCTAssertEqual(shares[2].fraction, 1.0 / 6.0, accuracy: 1e-9)
        XCTAssertEqual(shares.map(\.fraction).reduce(0, +), 1, accuracy: 1e-9)
    }

    func testSharesTieBreakByNameAndEmptyInput() {
        let sessions = [
            session("Zeta", date(2026, 10, 9, 9), minutes: 10),
            session("Alpha", date(2026, 10, 10, 9), minutes: 10),
        ]

        XCTAssertEqual(engine.shares(sessions).map(\.name), ["Alpha", "Zeta"])
        XCTAssertEqual(engine.shares([]), [])
    }
}
```

- [ ] **Step 2: Run the StatsEngine tests and watch them fail**

Run from the repo root:

```bash
cd Tofu && xcodegen generate && xcodebuild -project Tofu.xcodeproj -scheme Tofu -destination 'platform=macOS' test -only-testing:TofuTests/StatsEngineTests 2>&1 | tail -30
```

Expected: the test target does not compile. The output contains `error: cannot find type 'StatsEngine' in scope` (the "Testing failed:" summary shows it capitalized), and it ends with `** TEST FAILED **`. The compiler stops at this missing type, so `StatsRange` may not be reported yet.

- [ ] **Step 3: Implement StatsEngine**

Create `Tofu/Tofu/Engine/StatsEngine.swift`:

```swift
import Foundation

/// Time range shown by the stats bar chart.
enum StatsRange: String, CaseIterable, Identifiable {
    case day, week, month

    var id: String { rawValue }

    /// Segmented-control title.
    var title: String {
        switch self {
        case .day: return "Day"
        case .week: return "Week"
        case .month: return "Month"
        }
    }
}

/// One chart bar: minutes per subject for one day, week or month.
struct StatsBucket: Identifiable, Equatable {
    let start: Date
    let label: String                       // day: "Oct 10", week: "Oct 4", month: "Oct"
    let minutesBySubject: [String: Double]
    var id: Date { start }
    var totalMinutes: Double { minutesBySubject.values.reduce(0, +) }
}

/// Numbers for the summary cards (spec §10).
struct StatsSummary: Equatable {
    var today: TimeInterval
    var thisWeek: TimeInterval
    var currentStreak: Int
    var longestStreak: Int
    var sessionCount: Int
    var average: TimeInterval
    var longest: TimeInterval
    var blockedAttempts: Int
    var closedTabs: Int
    var bails: Int
}

/// Total time of one subject and its fraction of all tracked time.
struct SubjectShare: Identifiable, Equatable {
    let name: String
    let seconds: TimeInterval
    let fraction: Double
    var id: String { name }
}

/// Pure aggregation of sessions into chart buckets, summary numbers and per-subject shares.
/// Sessions with `end == nil` (still active) are ignored everywhere. A session belongs to the
/// calendar day / week / month of its `start` (no midnight splitting).
struct StatsEngine {
    static let streakThreshold: TimeInterval = 300
    static let otherLabel = "Other"
    let calendar: Calendar
    let now: Date

    init(calendar: Calendar = .current, now: Date = Date()) {
        self.calendar = calendar
        self.now = now
    }

    /// Ignores sessions with end == nil. Oldest -> newest. day: 14 buckets, week: 12, month: 12.
    /// Subjects outside the top `topSubjects` by total time (in the given sessions) are merged into otherLabel.
    func buckets(_ sessions: [Session], range: StatsRange, topSubjects: Int = 5) -> [StatsBucket] {
        let ended = Self.ended(sessions)
        let kept = topNames(ended, limit: topSubjects)
        let starts = bucketStarts(range)
        var minutes: [Date: [String: Double]] = [:]
        for start in starts { minutes[start] = [:] }
        for session in ended {
            let key = periodStart(range.component, for: session.start)
            guard var perSubject = minutes[key] else { continue }
            let name = kept.contains(session.subjectName) ? session.subjectName : Self.otherLabel
            perSubject[name, default: 0] += session.duration / 60
            minutes[key] = perSubject
        }
        let formatter = labelFormatter(range)
        return starts.map { start in
            StatsBucket(start: start, label: formatter.string(from: start), minutesBySubject: minutes[start] ?? [:])
        }
    }

    /// Summary cards. Streaks count days with >= streakThreshold seconds in total; the current streak
    /// ends today, or yesterday when today has not reached the threshold yet.
    func summary(_ sessions: [Session]) -> StatsSummary {
        let ended = Self.ended(sessions)
        let todayStart = periodStart(.day, for: now)
        let weekStart = periodStart(.weekOfYear, for: now)
        var today: TimeInterval = 0
        var thisWeek: TimeInterval = 0
        var perDay: [Date: TimeInterval] = [:]
        for session in ended {
            let day = periodStart(.day, for: session.start)
            perDay[day, default: 0] += session.duration
            if day == todayStart { today += session.duration }
            if periodStart(.weekOfYear, for: session.start) == weekStart { thisWeek += session.duration }
        }
        let qualifying = Set(perDay.filter { $0.value >= Self.streakThreshold }.keys)

        var cursor = qualifying.contains(todayStart) ? todayStart : shiftDay(todayStart, by: -1)
        var currentStreak = 0
        while qualifying.contains(cursor) && currentStreak < qualifying.count {
            currentStreak += 1
            cursor = shiftDay(cursor, by: -1)
        }

        var longestStreak = 0
        var run = 0
        var previous: Date?
        for day in qualifying.sorted() {
            if let previous, shiftDay(previous, by: 1) == day {
                run += 1
            } else {
                run = 1
            }
            longestStreak = max(longestStreak, run)
            previous = day
        }

        let durations = ended.map(\.duration)
        let total = durations.reduce(0, +)
        return StatsSummary(
            today: today,
            thisWeek: thisWeek,
            currentStreak: currentStreak,
            longestStreak: longestStreak,
            sessionCount: ended.count,
            average: ended.isEmpty ? 0 : total / Double(ended.count),
            longest: durations.max() ?? 0,
            blockedAttempts: ended.reduce(0) { $0 + $1.blockedAttempts },
            closedTabs: ended.reduce(0) { $0 + $1.closedTabs },
            bails: ended.filter { $0.outcome == .bailed }.count
        )
    }

    /// Desc by seconds; fraction of total (0 if total == 0).
    func shares(_ sessions: [Session]) -> [SubjectShare] {
        let totals = totalsByName(Self.ended(sessions))
        let total = totals.values.reduce(0, +)
        return Self.ranked(totals).map { entry in
            SubjectShare(name: entry.key, seconds: entry.value, fraction: total > 0 ? entry.value / total : 0)
        }
    }

    // MARK: - Helpers

    private static func ended(_ sessions: [Session]) -> [Session] {
        sessions.filter { $0.end != nil }
    }

    /// Seconds per subject name.
    private func totalsByName(_ sessions: [Session]) -> [String: TimeInterval] {
        var totals: [String: TimeInterval] = [:]
        for session in sessions { totals[session.subjectName, default: 0] += session.duration }
        return totals
    }

    /// Desc by value, ties by name asc (stable, deterministic ordering).
    private static func ranked(_ totals: [String: TimeInterval]) -> [(key: String, value: TimeInterval)] {
        totals.sorted { lhs, rhs in
            lhs.value != rhs.value ? lhs.value > rhs.value : lhs.key < rhs.key
        }
    }

    private func topNames(_ sessions: [Session], limit: Int) -> Set<String> {
        Set(Self.ranked(totalsByName(sessions)).prefix(max(0, limit)).map(\.key))
    }

    /// Start of the day / week / month containing `date`.
    private func periodStart(_ component: Calendar.Component, for date: Date) -> Date {
        calendar.dateInterval(of: component, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    /// Start of the day `days` days away from the day containing `day`.
    private func shiftDay(_ day: Date, by days: Int) -> Date {
        let shifted = calendar.date(byAdding: .day, value: days, to: day)
            ?? day.addingTimeInterval(TimeInterval(days) * 86_400)
        return periodStart(.day, for: shifted)
    }

    /// Period starts, oldest first, ending with the period containing `now`.
    private func bucketStarts(_ range: StatsRange) -> [Date] {
        let component = range.component
        let current = periodStart(component, for: now)
        return (0..<range.bucketCount).reversed().map { offset in
            let shifted = calendar.date(byAdding: component, value: -offset, to: current) ?? current
            return periodStart(component, for: shifted)
        }
    }

    private func labelFormatter(_ range: StatsRange) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = calendar.locale ?? Locale.current
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = range == .month ? "MMM" : "MMM d"
        return formatter
    }
}

private extension StatsRange {
    var component: Calendar.Component {
        switch self {
        case .day: return .day
        case .week: return .weekOfYear
        case .month: return .month
        }
    }

    var bucketCount: Int { self == .day ? 14 : 12 }
}
```

- [ ] **Step 4: Run the StatsEngine tests and watch them pass**

Run from the repo root:

```bash
cd Tofu && xcodegen generate && xcodebuild -project Tofu.xcodeproj -scheme Tofu -destination 'platform=macOS' test -only-testing:TofuTests/StatsEngineTests 2>&1 | tail -30
```

Expected: `Executed 20 tests, with 0 failures` and `** TEST SUCCEEDED **`.

If `testWeekBucketsAreTwelveCalendarWeeksEndingThisWeek` fails with `Oct 5`, the engine is ignoring `calendar.firstWeekday`. Week starts must come from `calendar.dateInterval(of: .weekOfYear, for:)` on the injected calendar, never from `Calendar.current`.

- [ ] **Step 5: Commit StatsEngine**

```bash
cd "$(git rev-parse --show-toplevel)" && git add Tofu/Tofu/Engine/StatsEngine.swift Tofu/TofuTests/StatsEngineTests.swift Tofu/Tofu.xcodeproj && git commit -F - <<'EOF'
Add StatsEngine: day/week/month buckets, summary cards, subject shares

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

- [ ] **Step 6: Write the failing DemoData tests**

Create `Tofu/TofuTests/DemoDataTests.swift`:

```swift
import XCTest
@testable import Tofu

final class DemoDataTests: XCTestCase {
    /// Gregorian, UTC, en_US_POSIX, weeks start on Sunday.
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = 1
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        guard let date = calendar.date(from: components) else { fatalError("invalid test date") }
        return date
    }

    /// Saturday 2026-10-10 15:00 UTC.
    private var now: Date { date(2026, 10, 10, 15) }

    func testDefaultSubjects() {
        let subjects = DemoData.defaultSubjects(now: now)
        guard subjects.count == 2 else { return XCTFail("expected 2 subjects, got \(subjects.count)") }

        XCTAssertEqual(subjects.map(\.name), ["CS128", "MATH241"])
        XCTAssertEqual(subjects.map(\.preset), [.split, .mainSide])
        XCTAssertEqual(subjects[0].sites, ["https://cs128.org", "https://prairielearn.org"])
        XCTAssertEqual(subjects[0].extraDomains, ["piazza.com"])
        XCTAssertEqual(subjects[1].sites, ["https://www.desmos.com/calculator"])
        XCTAssertEqual(subjects[1].extraDomains, [])
        XCTAssertNotEqual(subjects[0].id, subjects[1].id)
        for subject in subjects {
            XCTAssertEqual(subject.sites.count, subject.preset.siteCount)
            XCTAssertEqual(subject.createdAt, now)
            XCTAssertTrue(subject.allowedApps.isEmpty)
        }
    }

    func testGenerateIsDeterministicForTheSameSeed() {
        let subjects = DemoData.defaultSubjects(now: now)
        let first = DemoData.generate(subjects: subjects, now: now, calendar: calendar, seed: 7)
        let second = DemoData.generate(subjects: subjects, now: now, calendar: calendar, seed: 7)

        XCTAssertFalse(first.isEmpty)
        XCTAssertEqual(first, second)
        XCTAssertEqual(Set(first.map(\.id)).count, first.count, "ids must be unique")
    }

    func testDifferentSeedsGiveDifferentSessions() {
        let subjects = DemoData.defaultSubjects(now: now)
        let one = DemoData.generate(subjects: subjects, now: now, calendar: calendar, seed: 1)
        let two = DemoData.generate(subjects: subjects, now: now, calendar: calendar, seed: 2)

        XCTAssertNotEqual(one.map(\.start), two.map(\.start))
    }

    func testSessionsAreEndedDemoSessionsWithinTheLastThirtyDays() {
        let subjects = DemoData.defaultSubjects(now: now)
        let sessions = DemoData.generate(subjects: subjects, days: 30, now: now, calendar: calendar)
        let earliest = now.addingTimeInterval(-30 * 86_400)

        XCTAssertGreaterThan(sessions.count, 10)
        XCTAssertEqual(sessions.map(\.start), sessions.map(\.start).sorted(), "oldest first")
        for session in sessions {
            XCTAssertTrue(session.isDemo)
            guard let end = session.end else {
                XCTFail("demo session without end")
                continue
            }
            XCTAssertLessThanOrEqual(end, now)
            XCTAssertGreaterThanOrEqual(session.start, earliest)
            XCTAssertEqual(session.lastHeartbeat, end)
            XCTAssertGreaterThanOrEqual(session.duration, 15 * 60)
            XCTAssertLessThanOrEqual(session.duration, 120 * 60)
            XCTAssertTrue((8...22).contains(calendar.component(.hour, from: session.start)))
            XCTAssertTrue((0...6).contains(session.blockedAttempts))
            XCTAssertTrue((0...4).contains(session.closedTabs))
        }
    }

    func testOutcomesAreMostlyCompletedAndBailsOnlyHappenInGoalMode() {
        let subjects = DemoData.defaultSubjects(now: now)
        let sessions = DemoData.generate(subjects: subjects, days: 90, now: now, calendar: calendar)
        let bails = sessions.filter { $0.outcome == .bailed }
        let goals = sessions.filter { $0.mode.goalMinutes != nil }

        XCTAssertTrue(sessions.allSatisfy { $0.outcome == .completed || $0.outcome == .bailed })
        XCTAssertGreaterThan(bails.count, 0)
        XCTAssertLessThan(Double(bails.count) / Double(sessions.count), 0.25)
        XCTAssertGreaterThan(Double(goals.count) / Double(sessions.count), 0.4)
        XCTAssertLessThan(Double(goals.count) / Double(sessions.count), 0.8)
        for session in sessions {
            if let goal = session.mode.goalMinutes {
                XCTAssertTrue([25, 50, 90].contains(goal))
                if session.outcome == .bailed {
                    XCTAssertLessThan(session.duration, TimeInterval(goal * 60))
                } else {
                    XCTAssertEqual(session.duration, TimeInterval(goal * 60))
                }
            } else {
                XCTAssertEqual(session.outcome, .completed, "open sessions never bail")
            }
        }
    }

    func testUsesOnlyTheGivenSubjects() {
        let subjects = DemoData.defaultSubjects(now: now)
        let namesByID = Dictionary(uniqueKeysWithValues: subjects.map { ($0.id, $0.name) })
        let sessions = DemoData.generate(subjects: subjects, now: now, calendar: calendar)

        for session in sessions {
            XCTAssertEqual(namesByID[session.subjectID], session.subjectName)
        }
        XCTAssertEqual(Set(sessions.map(\.subjectName)), ["CS128", "MATH241"])
    }

    func testNothingEndsAfterNowEarlyInTheMorning() {
        let earlyNow = date(2026, 10, 10, 8, 30)
        let sessions = DemoData.generate(subjects: DemoData.defaultSubjects(now: earlyNow), days: 30,
                                         now: earlyNow, calendar: calendar)

        XCTAssertFalse(sessions.isEmpty)
        XCTAssertTrue(sessions.allSatisfy { ($0.end ?? .distantFuture) <= earlyNow })
    }

    func testEmptyInputsGiveNoSessions() {
        XCTAssertEqual(DemoData.generate(subjects: [], now: now, calendar: calendar), [])
        XCTAssertEqual(DemoData.generate(subjects: DemoData.defaultSubjects(now: now), days: 0,
                                         now: now, calendar: calendar), [])
    }
}
```

- [ ] **Step 7: Run the DemoData tests and watch them fail**

Run from the repo root:

```bash
cd Tofu && xcodegen generate && xcodebuild -project Tofu.xcodeproj -scheme Tofu -destination 'platform=macOS' test -only-testing:TofuTests/DemoDataTests 2>&1 | tail -30
```

Expected: the test target does not compile. The output contains `error: cannot find 'DemoData' in scope` and ends with `** TEST FAILED **`.

- [ ] **Step 8: Implement DemoData**

Create `Tofu/Tofu/Engine/DemoData.swift`. `SplitMix64` is `private` to this file on purpose: it is an implementation detail, and keeping it private avoids name clashes.

```swift
import Foundation

/// Seeded demo content so the stats screens look full (spec §10 "Demo data").
enum DemoData {
    private static let goalChoices = [25, 50, 90]

    /// CS128 (split) and MATH241 (mainSide) with example sites.
    static func defaultSubjects(now: Date) -> [Subject] {
        [
            Subject(name: "CS128", preset: .split,
                    sites: ["https://cs128.org", "https://prairielearn.org"],
                    extraDomains: ["piazza.com"], createdAt: now),
            Subject(name: "MATH241", preset: .mainSide,
                    sites: ["https://www.desmos.com/calculator"], createdAt: now),
        ]
    }

    /// Deterministic (SplitMix64 seeded) sessions over the last `days` days, all isDemo = true, end set.
    /// Per day (today included): 0-3 non-overlapping sessions starting between 08:00 and 22:00.
    /// 60% goal mode (25/50/90 min): completed at exactly the goal, or (1 in 6) bailed after 15 min..goal-1.
    /// 40% open mode: completed after 15-120 min. Sessions that would end after `now` are dropped.
    /// Same inputs + seed always produce the same sessions (including ids), oldest first.
    static func generate(subjects: [Subject], days: Int = 30, now: Date, calendar: Calendar = .current,
                         seed: UInt64 = 42) -> [Session] {
        guard !subjects.isEmpty, days > 0 else { return [] }
        var rng = SplitMix64(seed: seed)
        let today = calendar.startOfDay(for: now)
        var sessions: [Session] = []

        for offset in stride(from: days - 1, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let count = rng.int(4)                         // 0-3 sessions
            var minuteOfDay = 8 * 60 + rng.int(181)        // first start 08:00-11:00
            for _ in 0..<count {
                guard minuteOfDay <= 22 * 60,
                      let start = calendar.date(bySettingHour: minuteOfDay / 60, minute: minuteOfDay % 60,
                                                second: 0, of: day)
                else { break }
                let subject = subjects[rng.int(subjects.count)]
                let mode: SessionMode = rng.int(10) < 6
                    ? .goal(minutes: goalChoices[rng.int(goalChoices.count)])
                    : .open
                let bailed = mode.goalMinutes != nil && rng.int(6) == 0
                let minutes: Int
                if let goal = mode.goalMinutes {
                    minutes = bailed ? 15 + rng.int(goal - 15) : goal
                } else {
                    minutes = 15 + rng.int(106)                // 15-120 min
                }
                let attempts = rng.int(7)                      // 0-6
                let tabs = rng.int(5)                          // 0-4
                let id = rng.uuid()
                minuteOfDay += minutes + 30 + rng.int(121)     // 30-150 min break before the next one

                let end = start.addingTimeInterval(TimeInterval(minutes * 60))
                guard end <= now else { continue }
                sessions.append(Session(id: id, subjectID: subject.id, subjectName: subject.name, mode: mode,
                                        start: start, end: end, lastHeartbeat: end,
                                        blockedAttempts: attempts, closedTabs: tabs,
                                        outcome: bailed ? .bailed : .completed, isDemo: true))
            }
        }
        return sessions
    }
}

/// SplitMix64 PRNG: tiny and fully deterministic for a given seed.
private struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Integer in 0..<upperBound (0 when upperBound <= 0).
    mutating func int(_ upperBound: Int) -> Int {
        guard upperBound > 0 else { return 0 }
        return Int(next() % UInt64(upperBound))
    }

    /// Version-4 UUID built from generator output.
    mutating func uuid() -> UUID {
        let high = next()
        let low = next()
        var b = [UInt8](repeating: 0, count: 16)
        for i in 0..<8 {
            b[i] = UInt8(truncatingIfNeeded: high >> (56 - 8 * i))
            b[8 + i] = UInt8(truncatingIfNeeded: low >> (56 - 8 * i))
        }
        b[6] = (b[6] & 0x0F) | 0x40   // version 4
        b[8] = (b[8] & 0x3F) | 0x80   // RFC 4122 variant
        return UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
                           b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
    }
}
```

- [ ] **Step 9: Run the DemoData and StatsEngine tests and watch them pass**

Run from the repo root:

```bash
cd Tofu && xcodegen generate && xcodebuild -project Tofu.xcodeproj -scheme Tofu -destination 'platform=macOS' test -only-testing:TofuTests/DemoDataTests -only-testing:TofuTests/StatsEngineTests 2>&1 | tail -30
```

Expected: `Executed 28 tests, with 0 failures` and `** TEST SUCCEEDED **`. That is 8 DemoData tests plus 20 StatsEngine tests.

For reference, with the default seed 42, 30 days and the UTC test calendar, `generate` returns 43 sessions: 1355 min of CS128 and 868 min of MATH241 in total, with 9 bails. The tests do not assert these exact numbers. They are only a sanity check if you print the output while debugging.

- [ ] **Step 10: Run the full test suite**

Run from the repo root:

```bash
cd Tofu && xcodegen generate && xcodebuild -project Tofu.xcodeproj -scheme Tofu -destination 'platform=macOS' test 2>&1 | tail -30
```

Expected: `** TEST SUCCEEDED **`. All tests from Tasks 1–11 pass.

- [ ] **Step 11: Commit DemoData**

```bash
cd "$(git rev-parse --show-toplevel)" && git add Tofu/Tofu/Engine/DemoData.swift Tofu/TofuTests/DemoDataTests.swift Tofu/Tofu.xcodeproj && git commit -F - <<'EOF'
Add DemoData: default subjects and seeded deterministic demo sessions

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

### Task 12: AppModel + DiscordAnnouncer

`AppModel` is the app's root state. It holds the persisted `StoreData`, the sidebar selection and the live `SessionEngine`, and it saves after every mutation. `DiscordAnnouncer` is the live `Announcing` used by the engine. It posts through `DiscordClient.broadcast` in a background `Task`, so a slow or broken Discord never blocks or crashes a session.

Design notes:
- **Two-phase init.** The live engine needs an announcer, and the announcer needs the model's settings. But the model can't be referenced until its stored properties, including `engine`, are set. So the live `init(store:)` first creates a small `ModelBox` (a weak reference). The announcer's closures read the model through that box. The init then builds the engine and finishes the model, and only then sets `box.model = self`. Both public inits are `convenience` inits that delegate to one private designated init. They keep the binding call signatures (`AppModel()`, `AppModel(store:)`, `AppModel(store:engine:)`).
- **Test init wiring.** The test init `init(store:engine:)` also loads the store and sets `engine.onSessionChanged` to `upsertSession`. That way every session create, heartbeat, counter change and end is persisted, in tests and live.
- **`loadDemoData()`.** It removes earlier demo sessions before appending a fresh set. `DemoData.generate` is deterministic (seed 42), so loading twice would otherwise duplicate session ids. `clearDemoData()` removes only `isDemo` sessions.
- **`lockIn`.** It uses `settings.displayName`, and falls back to `NSFullUserName()` when the name is blank.
- **Keychain.** `discordToken` and `setDiscordToken` read and write the real Keychain item. That is why no test calls them; the tests never touch the real token.
- **`announce`.** It returns at once, without creating a client, when Discord is disabled or the trimmed token is empty. Otherwise it broadcasts in a `Task`, then either merges `report.posted` into the current channel cache through `onCacheUpdate`, or shows the single toast `Discord: couldn't post (check bot token/permissions)` when nothing was posted. This covers **Review Focus 5** on the announcer side.

**Files:**
- Create: `Tofu/Tofu/Discord/DiscordAnnouncer.swift`
- Create: `Tofu/Tofu/App/AppModel.swift`
- Modify (regenerated): `Tofu/Tofu.xcodeproj/project.pbxproj`
- Test: `Tofu/TofuTests/DiscordAnnouncerTests.swift`
- Test: `Tofu/TofuTests/AppModelTests.swift`

**Interfaces:**
- Consumes:
  - Task 2:
    - `struct StoreData { var version: Int; var subjects: [Subject]; var sessions: [Session]; var settings: AppSettings; static var empty: StoreData }`
    - `struct AppSettings { var displayName: String; var discordEnabled: Bool; var giveUpTemplate: String; var channelCache: [String: String] }`
    - `struct Subject`, `struct Session` (`id`, `subjectID`, `subjectName`, `end`, `isDemo`, `duration`), `enum SessionMode`
    - `final class Store { let fileURL: URL; init(fileURL: URL); static func defaultURL() -> URL; func load() -> StoreLoadResult; func save(_ data: StoreData) throws }`
    - `struct StoreLoadResult { var data: StoreData; var warning: String? }`
    - `enum Secrets { static let discordService: String; static let discordAccount: String }`
    - `enum Keychain { static func get(service: String, account: String) -> String?; @discardableResult static func set(_ value: String, service: String, account: String) -> Bool; static func delete(service: String, account: String) }`
  - Task 3: `@MainActor static func ScreenGeometry.mainVisibleFrame() -> CGRect?`; `@MainActor static func ScreenGeometry.primaryHeight() -> CGFloat`
  - Task 5: `static func DiscordMessages.start(name: String, subject: String, mode: SessionMode) -> String` (tests)
  - Task 6:
    - `final class DiscordClient { init(token: String, transport: HTTPTransport = URLSessionTransport(), sleep: @escaping (TimeInterval) async -> Void = { seconds in try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000)) }); func broadcast(_ content: String, channelCache: [String: String]) async -> DiscordPostReport }`
    - `struct DiscordPostReport { var posted: [String: String]; var failedGuilds: [String] }`
    - test helper `MockTransport`
  - Task 7: `@MainActor final class WorkspaceController { init() }`; `@MainActor final class AppBlocker { init(fallbackBundleID: String = "com.google.Chrome") }`
  - Task 8: `@MainActor final class ChromeController { init() }`
  - Task 9: `@MainActor protocol Toasting: AnyObject { func show(_ message: String) }`; `ToastCenter.shared`
  - Task 10:
    - `@MainActor protocol Announcing: AnyObject { func announce(_ content: String) }`
    - `SessionEngine` (`init(workspace:blocker:chrome:toaster:announcer:ownBundleID:clock:visibleFrame:primaryHeight:startsTimers:)`, `isLocked`, `onSessionChanged`, `start(subject:mode:displayName:) async`, `finish() async`)
    - test helpers `EngineHarness`, `FakeToaster`, `FakeAnnouncer`, `TestClock`
  - Task 11: `static func DemoData.defaultSubjects(now: Date) -> [Subject]`; `static func DemoData.generate(subjects: [Subject], days: Int = 30, now: Date, calendar: Calendar = .current, seed: UInt64 = 42) -> [Session]`
- Produces (binding):
  ```swift
  enum SidebarItem: Hashable {
      case subject(UUID)
      case stats
      case settings
  }

  @Observable @MainActor final class AppModel {
      var data: StoreData
      var selection: SidebarItem?
      let store: Store
      let engine: SessionEngine
      /// Loads store (shows warning toast if any), builds live engine with real controllers.
      convenience init(store: Store = Store(fileURL: Store.defaultURL()))
      /// Test initializer: injected engine.
      convenience init(store: Store, engine: SessionEngine)
      func subject(id: UUID) -> Subject?
      func addSubject(_ subject: Subject)          // also selects it
      func updateSubject(_ subject: Subject)
      func deleteSubject(id: UUID)                 // keeps the subject's sessions
      func upsertSession(_ session: Session)
      func updateSettings(_ mutate: (inout AppSettings) -> Void)
      func save()
      func lockIn(subjectID: UUID, mode: SessionMode) async
      var discordToken: String? { get }
      func setDiscordToken(_ token: String?)       // nil or blank deletes
      func loadDemoData()
      func clearDemoData()
  }

  @MainActor final class DiscordAnnouncer: Announcing {
      static let failureMessage = "Discord: couldn't post (check bot token/permissions)"   // additive
      init(token: @escaping () -> String?, settings: @escaping () -> AppSettings,
           onCacheUpdate: @escaping ([String: String]) -> Void, toaster: Toasting,
           makeClient: @escaping (String) -> DiscordClient = { DiscordClient(token: $0) })
      func announce(_ content: String)
  }
  ```

- [ ] **Step 1: Write the failing DiscordAnnouncer tests**

Each test builds an `AnnouncerHarness`. It wires a real `DiscordClient` to a `MockTransport` through `makeClient`, with a no-op `sleep`. It also holds a `FakeToaster` and editable settings and token. `broadcast` runs off the main actor, so each test polls (`waitUntil`, every 10 ms for up to 1 s) for the observable end state: a cache update or a toast. The "nothing happens" tests wait 0.2 s and then assert that no client was created and no request was sent.

Create `Tofu/TofuTests/DiscordAnnouncerTests.swift`:

```swift
import XCTest
@testable import Tofu

/// A DiscordAnnouncer wired to a MockTransport-backed DiscordClient, a FakeToaster and editable settings.
@MainActor private final class AnnouncerHarness {
    var settings = AppSettings(displayName: "Alex", discordEnabled: true)
    var token: String? = "test-token"
    private(set) var cacheUpdates: [[String: String]] = []
    private(set) var clientTokens: [String] = []
    let toaster = FakeToaster()
    let transport: MockTransport
    private(set) var announcer: DiscordAnnouncer!

    init(handler: @escaping (URLRequest) -> (Int, Data)) {
        let transport = MockTransport(handler: handler)
        self.transport = transport
        announcer = DiscordAnnouncer(
            token: { [weak self] in self?.token },
            settings: { [weak self] in self?.settings ?? AppSettings(discordEnabled: false) },
            onCacheUpdate: { [weak self] cache in self?.cacheUpdates.append(cache) },
            toaster: toaster,
            makeClient: { [weak self] token in
                self?.clientTokens.append(token)
                return DiscordClient(token: token, transport: transport, sleep: { _ in })
            })
    }
}

private let okBody = MockTransport.json("{}")

/// One guild "1" with text channels "10" (position 0) and "11" (position 1).
private func oneGuild(postStatus: @escaping (String) -> Int) -> (URLRequest) -> (Int, Data) {
    { request in
        let path = request.url?.path ?? ""
        switch path {
        case "/api/v10/users/@me/guilds":
            return (200, MockTransport.json(#"[{"id": "1", "name": "Study Hall"}]"#))
        case "/api/v10/guilds/1/channels":
            return (200, MockTransport.json("""
            [{"id": "10", "name": "general", "type": 0, "position": 0},
             {"id": "11", "name": "random", "type": 0, "position": 1}]
            """))
        default:
            let channelID = path.split(separator: "/").dropLast().last.map(String.init) ?? ""
            return (postStatus(channelID), okBody)
        }
    }
}

@MainActor
final class DiscordAnnouncerTests: XCTestCase {
    /// Polls `condition` every 10 ms for up to `timeout` seconds while the announcer's Task runs.
    private func waitUntil(timeout: TimeInterval = 1, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    func testDisabledSendsNothing() async {
        let h = AnnouncerHarness(handler: oneGuild { _ in 200 })
        h.settings.discordEnabled = false

        h.announcer.announce("🔒 **Alex** is locked in on **CS128**")
        await waitUntil(timeout: 0.2) { false }

        XCTAssertEqual(h.clientTokens, [])
        XCTAssertEqual(h.transport.requests.count, 0)
        XCTAssertEqual(h.toaster.messages, [])
        XCTAssertEqual(h.cacheUpdates, [])
    }

    func testMissingOrBlankTokenSendsNothing() async {
        let h = AnnouncerHarness(handler: oneGuild { _ in 200 })
        h.token = nil
        h.announcer.announce("hello")
        h.token = "   \n"
        h.announcer.announce("hello")
        await waitUntil(timeout: 0.2) { false }

        XCTAssertEqual(h.clientTokens, [])
        XCTAssertEqual(h.transport.requests.count, 0)
        XCTAssertEqual(h.toaster.messages, [])
    }

    func testSuccessMergesPostedChannelIntoCache() async throws {
        let h = AnnouncerHarness(handler: oneGuild { _ in 200 })
        h.token = "  test-token \n"
        h.settings.channelCache = ["9": "99"]

        h.announcer.announce("🔒 **Alex** is locked in on **CS128**")
        await waitUntil { !h.cacheUpdates.isEmpty }

        XCTAssertEqual(h.cacheUpdates, [["9": "99", "1": "10"]])
        XCTAssertEqual(h.toaster.messages, [])
        XCTAssertEqual(h.clientTokens, ["test-token"])
        XCTAssertEqual(h.transport.log, [
            "GET /api/v10/users/@me/guilds",
            "GET /api/v10/guilds/1/channels",
            "POST /api/v10/channels/10/messages",
        ])
        let post = try XCTUnwrap(h.transport.requests.last)
        XCTAssertEqual(post.value(forHTTPHeaderField: "Authorization"), "Bot test-token")
        let body = try XCTUnwrap(post.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["content"] as? String, "🔒 **Alex** is locked in on **CS128**")
    }

    func testForbiddenChannelFallsThroughAndCachesTheWorkingOne() async {
        let h = AnnouncerHarness(handler: oneGuild { channelID in channelID == "10" ? 403 : 200 })

        h.announcer.announce("hello")
        await waitUntil { !h.cacheUpdates.isEmpty }

        XCTAssertEqual(h.cacheUpdates, [["1": "11"]])
        XCTAssertEqual(h.toaster.messages, [])
    }

    func testEveryChannelFailingShowsOneToastAndKeepsCache() async {
        let h = AnnouncerHarness(handler: oneGuild { _ in 403 })
        h.settings.channelCache = ["1": "10"]

        h.announcer.announce("hello")
        await waitUntil { !h.toaster.messages.isEmpty }

        XCTAssertEqual(h.toaster.messages, ["Discord: couldn't post (check bot token/permissions)"])
        XCTAssertEqual(h.cacheUpdates, [])
        XCTAssertEqual(h.transport.log.filter { $0.hasPrefix("POST") }.count, 2)
    }

    func testBadTokenReturnsImmediatelyAndShowsOneToast() async {
        let h = AnnouncerHarness(handler: { _ in (401, MockTransport.json(#"{"message": "401: Unauthorized"}"#)) })

        h.announcer.announce("hello")
        XCTAssertEqual(h.toaster.messages, [], "announce must not wait for the network")
        await waitUntil { !h.toaster.messages.isEmpty }

        XCTAssertEqual(h.toaster.messages, [DiscordAnnouncer.failureMessage])
        XCTAssertEqual(h.transport.log, ["GET /api/v10/users/@me/guilds"])
        XCTAssertEqual(h.cacheUpdates, [])
    }
}
```

- [ ] **Step 2: Run the DiscordAnnouncer tests and watch them fail**

Run from the repo root:

```bash
cd Tofu && xcodegen generate && xcodebuild -project Tofu.xcodeproj -scheme Tofu -destination 'platform=macOS' test -only-testing:TofuTests/DiscordAnnouncerTests 2>&1 | tail -30
```

Expected: the test target fails to compile with `error: cannot find type 'DiscordAnnouncer' in scope` (the summary shows `Cannot find type 'DiscordAnnouncer' in scope`), followed by `** TEST FAILED **`.

- [ ] **Step 3: Implement DiscordAnnouncer**

Create `Tofu/Tofu/Discord/DiscordAnnouncer.swift`:

```swift
import Foundation

/// Live `Announcing`: posts session messages to every Discord server the bot is in (spec §9).
/// Fire-and-forget: `announce` returns at once and never throws; failures end up as one toast.
@MainActor final class DiscordAnnouncer: Announcing {
    static let failureMessage = "Discord: couldn't post (check bot token/permissions)"

    private let token: () -> String?
    private let settings: () -> AppSettings
    private let onCacheUpdate: ([String: String]) -> Void
    private let toaster: Toasting
    private let makeClient: (String) -> DiscordClient

    init(token: @escaping () -> String?, settings: @escaping () -> AppSettings,
         onCacheUpdate: @escaping ([String: String]) -> Void, toaster: Toasting,
         makeClient: @escaping (String) -> DiscordClient = { DiscordClient(token: $0) }) {
        self.token = token
        self.settings = settings
        self.onCacheUpdate = onCacheUpdate
        self.toaster = toaster
        self.makeClient = makeClient
    }

    /// Does nothing when Discord is disabled or there is no token. Otherwise broadcasts in a Task:
    /// channels that accepted the message are merged into the channel cache; if nothing was posted,
    /// one toast is shown.
    func announce(_ content: String) {
        let current = settings()
        guard current.discordEnabled else { return }
        let botToken = (token() ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !botToken.isEmpty else { return }
        let client = makeClient(botToken)
        let cache = current.channelCache
        Task {
            let report = await client.broadcast(content, channelCache: cache)
            self.handle(report)
        }
    }

    private func handle(_ report: DiscordPostReport) {
        guard !report.posted.isEmpty else {
            toaster.show(Self.failureMessage)
            return
        }
        var merged = settings().channelCache
        for (guildID, channelID) in report.posted {
            merged[guildID] = channelID
        }
        onCacheUpdate(merged)
    }
}
```

- [ ] **Step 4: Run the DiscordAnnouncer tests and watch them pass**

Run from the repo root:

```bash
cd Tofu && xcodegen generate && xcodebuild -project Tofu.xcodeproj -scheme Tofu -destination 'platform=macOS' test -only-testing:TofuTests/DiscordAnnouncerTests 2>&1 | tail -30
```

Expected: `Executed 6 tests, with 0 failures (0 unexpected)` and `** TEST SUCCEEDED **`. The two "sends nothing" tests take about 0.2 s each; the others finish in a few milliseconds.

- [ ] **Step 5: Commit the announcer**

```bash
cd "$(git rev-parse --show-toplevel)" && git add Tofu/Tofu/Discord/DiscordAnnouncer.swift Tofu/TofuTests/DiscordAnnouncerTests.swift Tofu/Tofu.xcodeproj && git commit -F - <<'EOF'
Add DiscordAnnouncer: background broadcast, cache update, one failure toast

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

- [ ] **Step 6: Write the failing AppModel tests**

Every test uses a `Store` in a fresh temp directory, removed by `addTeardownBlock`, and the fake engine from `EngineHarness`. The real `store.json` and the Keychain are never touched. "Persisted" is always checked by loading a **new** `Store` from the same file. Dates are whole seconds, because the ISO 8601 JSON keeps whole seconds only.

Create `Tofu/TofuTests/AppModelTests.swift`:

```swift
import XCTest
@testable import Tofu

@MainActor
final class AppModelTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_760_000_000)   // whole seconds: ISO8601 keeps them exactly

    /// A Store in a fresh temp directory that is deleted after the test (the real store.json is never touched).
    private func makeStore() throws -> Store {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppModelTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return Store(fileURL: directory.appendingPathComponent("store.json"))
    }

    /// What a fresh launch would read back from the same file.
    private func reloaded(_ store: Store) -> StoreData {
        Store(fileURL: store.fileURL).load().data
    }

    private func makeSubject(_ name: String = "CS128") -> Subject {
        Subject(name: name, preset: .split, sites: ["https://cs128.org", "https://prairielearn.org"],
                extraDomains: ["piazza.com"], createdAt: t0)
    }

    private func endedSession(for subject: Subject, isDemo: Bool = false) -> Session {
        Session(subjectID: subject.id, subjectName: subject.name, mode: .goal(minutes: 25), start: t0,
                end: t0.addingTimeInterval(1500), outcome: .completed, isDemo: isDemo)
    }

    // MARK: Loading

    func testFreshStoreStartsEmptyWithNoSelection() throws {
        let model = AppModel(store: try makeStore(), engine: EngineHarness().engine)
        XCTAssertEqual(model.data, StoreData.empty)
        XCTAssertNil(model.selection)
    }

    func testSelectionDefaultsToFirstSubject() throws {
        let store = try makeStore()
        let first = makeSubject("CS128")
        let second = makeSubject("MATH241")
        try store.save(StoreData(subjects: [first, second]))

        let model = AppModel(store: store, engine: EngineHarness().engine)

        XCTAssertEqual(model.data.subjects, [first, second])
        XCTAssertEqual(model.selection, .subject(first.id))
    }

    // MARK: Subjects

    func testAddSubjectPersistsAndSelectsIt() throws {
        let store = try makeStore()
        let model = AppModel(store: store, engine: EngineHarness().engine)
        let subject = makeSubject()

        model.addSubject(subject)

        XCTAssertEqual(model.selection, .subject(subject.id))
        XCTAssertEqual(model.subject(id: subject.id), subject)
        XCTAssertEqual(reloaded(store).subjects, [subject])
    }

    func testUpdateSubjectPersists() throws {
        let store = try makeStore()
        let model = AppModel(store: store, engine: EngineHarness().engine)
        var subject = makeSubject()
        model.addSubject(subject)

        subject.name = "CS 128"
        subject.preset = .full
        subject.sites = ["https://cs128.org"]
        model.updateSubject(subject)

        XCTAssertEqual(model.data.subjects, [subject])
        XCTAssertEqual(reloaded(store).subjects, [subject])
    }

    func testUpdateUnknownSubjectChangesNothing() throws {
        let store = try makeStore()
        let model = AppModel(store: store, engine: EngineHarness().engine)
        model.addSubject(makeSubject())

        model.updateSubject(makeSubject("Ghost"))

        XCTAssertEqual(model.data.subjects.map(\.name), ["CS128"])
    }

    func testDeleteSubjectKeepsItsSessionsAndMovesSelection() throws {
        let store = try makeStore()
        let model = AppModel(store: store, engine: EngineHarness().engine)
        let doomed = makeSubject("CS128")
        let kept = makeSubject("MATH241")
        model.addSubject(doomed)
        model.addSubject(kept)
        model.upsertSession(endedSession(for: doomed))
        model.selection = .subject(doomed.id)

        model.deleteSubject(id: doomed.id)

        XCTAssertEqual(model.selection, .subject(kept.id))
        let data = reloaded(store)
        XCTAssertEqual(data.subjects, [kept])
        XCTAssertEqual(data.sessions.count, 1)
        XCTAssertEqual(data.sessions.first?.subjectName, "CS128")
    }

    func testDeletingLastSubjectClearsSelection() throws {
        let model = AppModel(store: try makeStore(), engine: EngineHarness().engine)
        let subject = makeSubject()
        model.addSubject(subject)

        model.deleteSubject(id: subject.id)

        XCTAssertNil(model.selection)
        XCTAssertTrue(model.data.subjects.isEmpty)
    }

    // MARK: Sessions

    func testUpsertSessionInsertsThenUpdates() throws {
        let store = try makeStore()
        let model = AppModel(store: store, engine: EngineHarness().engine)
        var session = endedSession(for: makeSubject())

        model.upsertSession(session)
        session.closedTabs = 3
        session.blockedAttempts = 2
        model.upsertSession(session)

        XCTAssertEqual(model.data.sessions, [session])
        XCTAssertEqual(reloaded(store).sessions, [session])
    }

    func testEngineSessionChangesArePersisted() async throws {
        let store = try makeStore()
        let harness = EngineHarness()
        let model = AppModel(store: store, engine: harness.engine)
        let subject = makeSubject()
        model.addSubject(subject)

        await model.lockIn(subjectID: subject.id, mode: .open)

        XCTAssertTrue(harness.engine.isLocked)
        let active = try XCTUnwrap(model.data.sessions.first)
        XCTAssertEqual(model.data.sessions.count, 1)
        XCTAssertNil(active.end)
        XCTAssertEqual(reloaded(store).sessions.map(\.id), [active.id])

        harness.clock.advance(600)
        await harness.engine.finish()

        let saved = try XCTUnwrap(reloaded(store).sessions.first)
        XCTAssertEqual(saved.id, active.id)
        XCTAssertEqual(saved.outcome, .completed)
        XCTAssertEqual(saved.duration, 600)
        XCTAssertEqual(model.data.sessions, [saved])
    }

    func testLockInPassesDisplayNameToTheEngine() async throws {
        let harness = EngineHarness()
        let model = AppModel(store: try makeStore(), engine: harness.engine)
        model.updateSettings { $0.displayName = "Alex" }
        let subject = makeSubject()
        model.addSubject(subject)

        await model.lockIn(subjectID: subject.id, mode: .goal(minutes: 25))

        XCTAssertEqual(harness.announcer.messages,
                       [DiscordMessages.start(name: "Alex", subject: "CS128", mode: .goal(minutes: 25))])
        XCTAssertTrue(harness.announcer.messages[0].contains("**Alex**"))
    }

    func testLockInWithBlankDisplayNameFallsBackToFullUserName() async throws {
        let harness = EngineHarness()
        let model = AppModel(store: try makeStore(), engine: harness.engine)
        model.updateSettings { $0.displayName = "   " }
        let subject = makeSubject()
        model.addSubject(subject)

        await model.lockIn(subjectID: subject.id, mode: .open)

        XCTAssertEqual(harness.announcer.messages,
                       [DiscordMessages.start(name: NSFullUserName(), subject: "CS128", mode: .open)])
    }

    func testLockInUnknownSubjectDoesNothing() async throws {
        let harness = EngineHarness()
        let model = AppModel(store: try makeStore(), engine: harness.engine)

        await model.lockIn(subjectID: UUID(), mode: .open)

        XCTAssertFalse(harness.engine.isLocked)
        XCTAssertEqual(harness.announcer.messages, [])
        XCTAssertTrue(model.data.sessions.isEmpty)
    }

    // MARK: Settings

    func testUpdateSettingsPersists() throws {
        let store = try makeStore()
        let model = AppModel(store: store, engine: EngineHarness().engine)

        model.updateSettings {
            $0.displayName = "Sam"
            $0.discordEnabled = true
            $0.giveUpTemplate = "I quit {subject}"
        }

        let settings = reloaded(store).settings
        XCTAssertEqual(settings.displayName, "Sam")
        XCTAssertTrue(settings.discordEnabled)
        XCTAssertEqual(settings.giveUpTemplate, "I quit {subject}")
    }

    // MARK: Demo data

    func testLoadDemoDataCreatesDefaultSubjectsWhenThereAreNone() throws {
        let store = try makeStore()
        let model = AppModel(store: store, engine: EngineHarness().engine)

        model.loadDemoData()

        XCTAssertEqual(model.data.subjects.map(\.name), ["CS128", "MATH241"])
        XCTAssertEqual(model.selection, model.data.subjects.first.map { .subject($0.id) })
        XCTAssertFalse(model.data.sessions.isEmpty)
        XCTAssertTrue(model.data.sessions.allSatisfy { $0.isDemo && $0.end != nil })
        XCTAssertEqual(reloaded(store).sessions.count, model.data.sessions.count)
    }

    func testLoadDemoDataUsesExistingSubjectsAndNeverDuplicates() throws {
        let model = AppModel(store: try makeStore(), engine: EngineHarness().engine)
        let subject = makeSubject("PHYS211")
        model.addSubject(subject)

        model.loadDemoData()
        model.loadDemoData()

        XCTAssertEqual(model.data.subjects, [subject])
        XCTAssertFalse(model.data.sessions.isEmpty)
        XCTAssertTrue(model.data.sessions.allSatisfy { $0.subjectID == subject.id && $0.subjectName == "PHYS211" })
        let ids = model.data.sessions.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testClearDemoDataRemovesOnlyDemoSessions() throws {
        let store = try makeStore()
        let model = AppModel(store: store, engine: EngineHarness().engine)
        let subject = makeSubject()
        model.addSubject(subject)
        let real = endedSession(for: subject)
        model.upsertSession(real)
        model.loadDemoData()
        XCTAssertGreaterThan(model.data.sessions.count, 1)

        model.clearDemoData()

        XCTAssertEqual(model.data.sessions, [real])
        XCTAssertEqual(model.data.subjects, [subject])
        XCTAssertEqual(reloaded(store).sessions, [real])
    }
}
```

- [ ] **Step 7: Run the AppModel tests and watch them fail**

Run from the repo root:

```bash
cd Tofu && xcodegen generate && xcodebuild -project Tofu.xcodeproj -scheme Tofu -destination 'platform=macOS' test -only-testing:TofuTests/AppModelTests 2>&1 | tail -30
```

Expected: the test target fails to compile with `error: cannot find 'AppModel' in scope`, followed by `** TEST FAILED **`.

- [ ] **Step 8: Implement AppModel**

Create `Tofu/Tofu/App/AppModel.swift`. `SidebarItem` lives here too. The store's load warning (a corrupt file that was backed up) is shown with `DispatchQueue.main.async`, after launch has finished, so the toast panel can find the screen.

```swift
import AppKit
import Foundation
import Observation

/// What the main window's sidebar has selected.
enum SidebarItem: Hashable {
    case subject(UUID)
    case stats
    case settings
}

/// Root app state: the persisted data, the sidebar selection and the session engine.
/// Every mutation saves `data` to the store right away.
@Observable @MainActor final class AppModel {
    var data: StoreData
    var selection: SidebarItem?
    let store: Store
    let engine: SessionEngine

    /// Loads store (shows warning toast if any), builds live engine with real controllers.
    convenience init(store: Store = Store(fileURL: Store.defaultURL())) {
        let loaded = store.load()
        // The announcer needs the model, but the model needs the engine (which needs the announcer).
        // The announcer's closures read the model through this box, which is filled in after init.
        let box = ModelBox()
        let announcer = DiscordAnnouncer(
            token: { Keychain.get(service: Secrets.discordService, account: Secrets.discordAccount) },
            settings: { box.model?.data.settings ?? AppSettings(discordEnabled: false) },
            onCacheUpdate: { cache in box.model?.updateSettings { $0.channelCache = cache } },
            toaster: ToastCenter.shared)
        let engine = SessionEngine(workspace: WorkspaceController(), blocker: AppBlocker(),
                                   chrome: ChromeController(), toaster: ToastCenter.shared,
                                   announcer: announcer,
                                   ownBundleID: Bundle.main.bundleIdentifier ?? "com.tofu.app",
                                   visibleFrame: { ScreenGeometry.mainVisibleFrame() },
                                   primaryHeight: { ScreenGeometry.primaryHeight() })
        self.init(store: store, loaded: loaded, engine: engine)
        box.model = self
        if let warning = loaded.warning {
            // After launch, so the toast panel can find the screen.
            DispatchQueue.main.async { ToastCenter.shared.show(warning) }
        }
    }

    /// Test initializer: injected engine.
    convenience init(store: Store, engine: SessionEngine) {
        self.init(store: store, loaded: store.load(), engine: engine)
    }

    private init(store: Store, loaded: StoreLoadResult, engine: SessionEngine) {
        self.store = store
        self.engine = engine
        self.data = loaded.data
        self.selection = loaded.data.subjects.first.map { SidebarItem.subject($0.id) }
        engine.onSessionChanged = { [weak self] session in
            self?.upsertSession(session)
        }
    }

    // MARK: Subjects

    func subject(id: UUID) -> Subject? {
        data.subjects.first { $0.id == id }
    }

    /// Appends the subject, selects it and saves.
    func addSubject(_ subject: Subject) {
        data.subjects.append(subject)
        selection = .subject(subject.id)
        save()
    }

    /// Replaces the subject with the same id (no-op if it is unknown) and saves.
    func updateSubject(_ subject: Subject) {
        guard let index = data.subjects.firstIndex(where: { $0.id == subject.id }) else { return }
        data.subjects[index] = subject
        save()
    }

    /// Removes the subject but keeps its sessions (stats use their `subjectName` snapshot).
    func deleteSubject(id: UUID) {
        data.subjects.removeAll { $0.id == id }
        if selection == .subject(id) {
            selection = data.subjects.first.map { SidebarItem.subject($0.id) }
        }
        save()
    }

    // MARK: Sessions

    /// Inserts a new session or replaces the one with the same id, then saves.
    func upsertSession(_ session: Session) {
        if let index = data.sessions.firstIndex(where: { $0.id == session.id }) {
            data.sessions[index] = session
        } else {
            data.sessions.append(session)
        }
        save()
    }

    /// Starts a session on the subject using the display name from settings.
    func lockIn(subjectID: UUID, mode: SessionMode) async {
        guard let subject = subject(id: subjectID) else { return }
        let trimmed = data.settings.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = trimmed.isEmpty ? NSFullUserName() : trimmed
        await engine.start(subject: subject, mode: mode, displayName: displayName)
    }

    // MARK: Settings

    func updateSettings(_ mutate: (inout AppSettings) -> Void) {
        mutate(&data.settings)
        save()
    }

    /// Writes `data` to the store. A failure is shown as a toast; the in-memory data stays intact.
    func save() {
        do {
            try store.save(data)
        } catch {
            NSLog("Tofu: saving failed: %@", error.localizedDescription)
            ToastCenter.shared.show("Couldn't save your data: \(error.localizedDescription)")
        }
    }

    /// The Discord bot token from the Keychain (never stored in store.json).
    var discordToken: String? {
        Keychain.get(service: Secrets.discordService, account: Secrets.discordAccount)
    }

    /// Saves a trimmed token to the Keychain; nil or blank deletes it.
    func setDiscordToken(_ token: String?) {
        let trimmed = (token ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            Keychain.delete(service: Secrets.discordService, account: Secrets.discordAccount)
        } else {
            Keychain.set(trimmed, service: Secrets.discordService, account: Secrets.discordAccount)
        }
    }

    // MARK: Demo data

    /// Adds CS128 and MATH241 when there are no subjects, then (re)seeds about 30 days of demo sessions.
    /// Earlier demo sessions are replaced, so loading twice never duplicates them.
    func loadDemoData() {
        let now = Date()
        if data.subjects.isEmpty {
            data.subjects = DemoData.defaultSubjects(now: now)
            if selection == nil {
                selection = data.subjects.first.map { SidebarItem.subject($0.id) }
            }
        }
        data.sessions.removeAll { $0.isDemo }
        data.sessions.append(contentsOf: DemoData.generate(subjects: data.subjects, now: now))
        save()
    }

    /// Removes every demo session. Subjects and real sessions are kept.
    func clearDemoData() {
        data.sessions.removeAll { $0.isDemo }
        save()
    }
}

/// Weak link from the live DiscordAnnouncer's closures back to the model (see `AppModel.init(store:)`).
@MainActor private final class ModelBox {
    weak var model: AppModel?
}
```

- [ ] **Step 9: Run the AppModel tests and watch them pass**

Run from the repo root:

```bash
cd Tofu && xcodegen generate && xcodebuild -project Tofu.xcodeproj -scheme Tofu -destination 'platform=macOS' test -only-testing:TofuTests/AppModelTests 2>&1 | tail -30
```

Expected: `Executed 16 tests, with 0 failures (0 unexpected)` and `** TEST SUCCEEDED **`.

- [ ] **Step 10: Run the full suite**

Run from the repo root:

```bash
cd Tofu && xcodegen generate && xcodebuild -project Tofu.xcodeproj -scheme Tofu -destination 'platform=macOS' test 2>&1 | tail -30
```

Expected: `** TEST SUCCEEDED **`, with every test from Tasks 1–12 passing. The app entry point is still Task 1's temporary one, so nothing creates the live `AppModel` yet. Task 13 adds that.

- [ ] **Step 11: Commit the model**

```bash
cd "$(git rev-parse --show-toplevel)" && git add Tofu/Tofu/App/AppModel.swift Tofu/TofuTests/AppModelTests.swift Tofu/Tofu.xcodeproj && git commit -F - <<'EOF'
Add AppModel: persisted subjects, sessions and settings around the engine

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

Expected: `git status --short` prints nothing.

---

### Task 13: UI shell

This task builds the main window: a sidebar of subjects (with total time) plus Stats and Settings, the subject detail with **LOCK IN**, the subject editor, the app picker and the lock-in sheet. It also installs the final app entry point and `AppDelegate`.

Some screens get their real versions in later tasks, so this task creates complete, compiling **placeholders** for them. Each placeholder is labeled in its file:

| Placeholder file | Replaced by |
|---|---|
| `UI/StatsView.swift` (`StatsView` and `SubjectStatsSection`) | Task 16 |
| `UI/SettingsView.swift` | Task 15 |
| `UI/LockedView.swift` | Task 14 |
| `UI/MainWindowPresenter.swift` (a no-op `WindowPresenting`) | Task 14 |

The logic behind the screens lives in three pure types, each written test-first:
- `SubjectValidator`: the editor's error messages, site normalization, site slots and extra-domain parsing.
- `AppCatalog`: scans `.app` bundles and filters the picker list.
- `LockInOption`: the lock-in lengths and their `SessionMode`.

Everything else is SwiftUI. It gets build checks and a manual walkthrough.

**Files:**
- Create: `Tofu/Tofu/Engine/SubjectValidator.swift`
- Create: `Tofu/Tofu/System/AppCatalog.swift`
- Create: `Tofu/Tofu/UI/Theme.swift`
- Create: `Tofu/Tofu/UI/PresetThumbnail.swift`
- Create (placeholder, replaced in Task 16): `Tofu/Tofu/UI/StatsView.swift`
- Create (placeholder, replaced in Task 15): `Tofu/Tofu/UI/SettingsView.swift`
- Create (placeholder, replaced in Task 14): `Tofu/Tofu/UI/LockedView.swift`
- Create (placeholder, replaced in Task 14): `Tofu/Tofu/UI/MainWindowPresenter.swift`
- Create: `Tofu/Tofu/UI/LockInSheet.swift`
- Create: `Tofu/Tofu/UI/AppPickerView.swift`
- Create: `Tofu/Tofu/UI/SubjectEditorView.swift`
- Create: `Tofu/Tofu/UI/SubjectDetailView.swift`
- Create: `Tofu/Tofu/UI/SidebarView.swift`
- Create: `Tofu/Tofu/UI/RootView.swift`
- Create: `Tofu/Tofu/App/AppDelegate.swift`
- Modify (replace whole file, final version): `Tofu/Tofu/App/TofuApp.swift`
- Modify (regenerated): `Tofu/Tofu.xcodeproj/project.pbxproj`
- Test: `Tofu/TofuTests/SubjectValidatorTests.swift`
- Test: `Tofu/TofuTests/AppCatalogTests.swift`
- Test: `Tofu/TofuTests/LockInOptionTests.swift`

**Interfaces:**
- Consumes:
  - Task 2: `enum LayoutPreset: CaseIterable, Identifiable { var siteCount: Int; var appHasZone: Bool; var title: String }`; `struct AllowedApp: Identifiable { var bundleID: String; var name: String }`; `struct Subject`; `enum SessionMode`
  - Task 3: `static func LayoutEngine.layout(_ preset: LayoutPreset, in visible: CGRect) -> LayoutResult` (thumbnail drawing)
  - Task 4: `static func DomainMatcher.normalizedURL(_ string: String) -> URL?`; `static func DomainMatcher.host(of urlString: String) -> String?`
  - Task 5: `static func TimeFormat.short(_ seconds: TimeInterval) -> String`; `static func TimeFormat.clock(_ seconds: TimeInterval) -> String`
  - Task 7: `BlockPolicy.alwaysAllowed: Set<String>` (`com.google.Chrome`, `com.apple.finder`)
  - Task 10: `SessionEngine` (`isLocked`, `subject`, `elapsed`, `remaining`, `presenter`, `finish()`, `terminateNow()`); `@MainActor protocol WindowPresenting: AnyObject { func enterLocked(appFrame: CGRect?); func exitLocked() }`
  - Task 12: `AppModel` (all members above), `enum SidebarItem`
- Produces (binding):
  ```swift
  // UI/Theme.swift (full file in Step 11):
  // Theme.radius (10); Theme.Space.xs/s/m/l/xl (4/8/16/24/40); Theme.grays; Theme.gray(at:);
  // Theme.timerFont(size:); Theme.titleFont; Theme.captionFont;
  // PrimaryButtonStyle, SecondaryButtonStyle, StatCard(title:value:)

  enum SubjectValidator {
      static func errors(name: String, sites: [String], preset: LayoutPreset) -> [String]
      static func sitesForSave(_ sites: [String], preset: LayoutPreset) -> [String]
      static func siteSlots(_ sites: [String]) -> [String]
      static func parseDomains(_ text: String) -> [String]
  }

  enum AppCatalog {
      static func defaultDirectories() -> [URL]
      static func scan(directories: [URL]) -> [AllowedApp]
      static func app(at bundleURL: URL) -> AllowedApp?
      static func filter(_ apps: [AllowedApp], query: String, excluding excluded: Set<String>) -> [AllowedApp]
  }

  enum LockInOption: Hashable, CaseIterable, Identifiable {
      case openEnded, minutes25, minutes50, minutes90, custom
      static let customRange: ClosedRange<Int>         // 5...240
      var title: String
      func mode(customMinutes: Int) -> SessionMode
  }

  struct PresetThumbnail: View { let preset: LayoutPreset }
  struct AppIcon: View { let bundleID: String }
  struct AppPickerView: View { @Binding var selection: [AllowedApp] }
  struct LockInSheet: View { let model: AppModel; let subject: Subject }
  struct SubjectEditorView: View { init(model: AppModel, subject: Subject?) }   // nil = new subject
  struct SubjectDetailView: View { let model: AppModel; let subject: Subject }
  struct SidebarView: View { @Bindable var model: AppModel }
  struct RootView: View { let model: AppModel }

  // Placeholders with their final signatures (bodies replaced later):
  struct StatsView: View { let model: AppModel }                                   // Task 16
  struct SubjectStatsSection: View { let model: AppModel; let subjectID: UUID }    // Task 16
  struct SettingsView: View { let model: AppModel }                                // Task 15
  struct LockedView: View { let model: AppModel }                                  // Task 14
  @MainActor final class MainWindowPresenter: WindowPresenting { init(model: AppModel) }   // Task 14

  @MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
      static var isRunningTests: Bool { get }
      var model: AppModel { get }                      // lazily created, never under tests
      func applicationDidFinishLaunching(_ notification: Notification)
      func applicationWillTerminate(_ notification: Notification)
  }
  @main struct TofuApp: App              // final
  ```

- [ ] **Step 1: Write the failing SubjectValidator tests**

The rules are:
- The name is required.
- The number of filled site fields must equal `preset.siteCount`.
- Every filled site must parse with `DomainMatcher.normalizedURL`, which adds `https://` when the scheme is missing.

Messages come in display order. The helpers turn the editor's text into what gets saved.

Create `Tofu/TofuTests/SubjectValidatorTests.swift`:

```swift
import XCTest
@testable import Tofu

final class SubjectValidatorTests: XCTestCase {
    // MARK: errors(name:sites:preset:)

    func testValidSplitSubjectHasNoErrors() {
        let errors = SubjectValidator.errors(name: "CS128", sites: ["https://cs128.org", "Piazza.com/class/x"],
                                             preset: .split)
        XCTAssertEqual(errors, [])
    }

    func testValidSingleSiteLayouts() {
        XCTAssertEqual(SubjectValidator.errors(name: "MATH241", sites: ["desmos.com"], preset: .full), [])
        XCTAssertEqual(SubjectValidator.errors(name: "MATH241", sites: ["desmos.com"], preset: .mainSide), [])
    }

    func testBlankNameIsRequired() {
        XCTAssertEqual(SubjectValidator.errors(name: "", sites: ["cs128.org"], preset: .full),
                       ["Name is required"])
        XCTAssertEqual(SubjectValidator.errors(name: "  \n", sites: ["cs128.org"], preset: .full),
                       ["Name is required"])
    }

    func testMissingSitesAskForThePresetCount() {
        XCTAssertEqual(SubjectValidator.errors(name: "CS128", sites: ["cs128.org", "  "], preset: .split),
                       ["Add 2 sites for this layout"])
        XCTAssertEqual(SubjectValidator.errors(name: "CS128", sites: [], preset: .thirds),
                       ["Add 2 sites for this layout"])
        XCTAssertEqual(SubjectValidator.errors(name: "CS128", sites: [""], preset: .full),
                       ["Add 1 site for this layout"])
    }

    func testTooManySitesAskForThePresetCount() {
        XCTAssertEqual(SubjectValidator.errors(name: "CS128", sites: ["a.com", "b.com"], preset: .full),
                       ["Add 1 site for this layout"])
    }

    func testInvalidSiteIsReportedByPosition() {
        XCTAssertEqual(SubjectValidator.errors(name: "CS128", sites: ["cs128.org", "not a url"], preset: .split),
                       ["Site 2 is not a valid URL"])
        XCTAssertEqual(SubjectValidator.errors(name: "CS128", sites: ["https://"], preset: .full),
                       ["Site 1 is not a valid URL"])
    }

    func testErrorsComeInDisplayOrder() {
        XCTAssertEqual(SubjectValidator.errors(name: " ", sites: ["%%%", ""], preset: .split),
                       ["Name is required", "Add 2 sites for this layout", "Site 1 is not a valid URL"])
    }

    // MARK: Helpers used when saving

    func testSitesForSaveAddsSchemeAndKeepsOnlyThePresetCount() {
        XCTAssertEqual(SubjectValidator.sitesForSave(["cs128.org", " https://prairielearn.org/pl "], preset: .split),
                       ["https://cs128.org", "https://prairielearn.org/pl"])
        XCTAssertEqual(SubjectValidator.sitesForSave(["cs128.org", "piazza.com"], preset: .full),
                       ["https://cs128.org"])
    }

    func testSiteSlotsAlwaysHaveAtLeastTwoEntries() {
        XCTAssertEqual(SubjectValidator.siteSlots([]), ["", ""])
        XCTAssertEqual(SubjectValidator.siteSlots(["https://a.com"]), ["https://a.com", ""])
        XCTAssertEqual(SubjectValidator.siteSlots(["https://a.com", "https://b.com"]), ["https://a.com", "https://b.com"])
    }

    func testParseDomainsNormalizesSplitsAndDeduplicates() {
        XCTAssertEqual(SubjectValidator.parseDomains("Piazza.com, https://www.stackoverflow.com/questions  docs.python.org,,piazza.com"),
                       ["piazza.com", "stackoverflow.com", "docs.python.org"])
        XCTAssertEqual(SubjectValidator.parseDomains(""), [])
        XCTAssertEqual(SubjectValidator.parseDomains(" ,  %%% "), [])
    }
}
```

- [ ] **Step 2: Run the SubjectValidator tests and watch them fail**

Run from the repo root:

```bash
cd Tofu && xcodegen generate && xcodebuild -project Tofu.xcodeproj -scheme Tofu -destination 'platform=macOS' test -only-testing:TofuTests/SubjectValidatorTests 2>&1 | tail -30
```

Expected: `error: cannot find 'SubjectValidator' in scope`, then `** TEST FAILED **`.

- [ ] **Step 3: Implement SubjectValidator**

Create `Tofu/Tofu/Engine/SubjectValidator.swift`:

```swift
import Foundation

/// Pure rules behind SubjectEditorView: validation messages and how typed input becomes a Subject.
enum SubjectValidator {
    /// Messages in display order; empty means the subject can be saved.
    /// `sites` are the visible site fields; blank entries do not count as sites.
    static func errors(name: String, sites: [String], preset: LayoutPreset) -> [String] {
        var errors: [String] = []
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Name is required")
        }
        let filled = sites.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if filled.count != preset.siteCount {
            errors.append("Add \(preset.siteCount) site\(preset.siteCount == 1 ? "" : "s") for this layout")
        }
        for (index, site) in sites.enumerated()
        where !site.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && DomainMatcher.normalizedURL(site) == nil {
            errors.append("Site \(index + 1) is not a valid URL")
        }
        return errors
    }

    /// The first `preset.siteCount` entries as full URLs ("cs128.org" -> "https://cs128.org").
    /// Blank or unparseable entries are dropped.
    static func sitesForSave(_ sites: [String], preset: LayoutPreset) -> [String] {
        sites.prefix(preset.siteCount).compactMap { DomainMatcher.normalizedURL($0)?.absoluteString }
    }

    /// Editor slots: always at least 2, so switching to a 1-site layout and back keeps the second site.
    static func siteSlots(_ sites: [String]) -> [String] {
        sites.count >= 2 ? sites : sites + Array(repeating: "", count: 2 - sites.count)
    }

    /// "Piazza.com, https://www.stackoverflow.com/questions  docs.python.org" -> normalized hosts,
    /// split on commas and whitespace, deduplicated in order, unparseable entries dropped.
    static func parseDomains(_ text: String) -> [String] {
        let separators = CharacterSet(charactersIn: ",").union(.whitespacesAndNewlines)
        var seen = Set<String>()
        var result: [String] = []
        for token in text.components(separatedBy: separators) where !token.isEmpty {
            guard let host = DomainMatcher.host(of: token), seen.insert(host).inserted else { continue }
            result.append(host)
        }
        return result
    }
}
```

- [ ] **Step 4: Run the SubjectValidator tests and watch them pass**

Run from the repo root:

```bash
cd Tofu && xcodegen generate && xcodebuild -project Tofu.xcodeproj -scheme Tofu -destination 'platform=macOS' test -only-testing:TofuTests/SubjectValidatorTests 2>&1 | tail -30
```

Expected: `Executed 10 tests, with 0 failures (0 unexpected)` and `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit SubjectValidator**

```bash
cd "$(git rev-parse --show-toplevel)" && git add Tofu/Tofu/Engine/SubjectValidator.swift Tofu/TofuTests/SubjectValidatorTests.swift Tofu/Tofu.xcodeproj && git commit -F - <<'EOF'
Add SubjectValidator for the subject editor

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

- [ ] **Step 6: Write the failing AppCatalog tests**

The tests build fake `.app` bundles (just `Contents/Info.plist`) in a temp directory, so they never depend on what is installed. The cases:
- a top-level app
- an app one subfolder down (like `/Applications/Utilities`)
- an app two levels down, which is ignored
- a bundle without `CFBundleIdentifier`, which is skipped
- the file-name fallback for the name
- a duplicate bundle ID across directories, where the first one wins
- a missing directory
- case-insensitive sorting

Create `Tofu/TofuTests/AppCatalogTests.swift`:

```swift
import XCTest
@testable import Tofu

final class AppCatalogTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppCatalogTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// Writes `<directory>/<path>/Contents/Info.plist` with the given keys and returns the bundle URL.
    @discardableResult
    private func makeApp(_ path: String, in directory: URL, info: [String: String]) throws -> URL {
        let bundleURL = directory.appendingPathComponent(path, isDirectory: true)
        let contents = bundleURL.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try plist.write(to: contents.appendingPathComponent("Info.plist"))
        return bundleURL
    }

    func testScanReadsTopLevelAndOneSubfolderLevelSortedByName() throws {
        let apps = root.appendingPathComponent("Applications", isDirectory: true)
        try makeApp("Zeta.app", in: apps, info: ["CFBundleIdentifier": "com.test.zeta", "CFBundleName": "Zeta"])
        try makeApp("alpha.app", in: apps, info: ["CFBundleIdentifier": "com.test.alpha",
                                                  "CFBundleName": "alpha", "CFBundleDisplayName": "alpha Display"])
        try makeApp("Utilities/Beta.app", in: apps, info: ["CFBundleIdentifier": "com.test.beta", "CFBundleName": "Beta"])
        try makeApp("Nested/Deeper/Gamma.app", in: apps, info: ["CFBundleIdentifier": "com.test.gamma"])
        try Data("not an app".utf8).write(to: apps.appendingPathComponent("notes.txt"))

        let found = AppCatalog.scan(directories: [apps])

        XCTAssertEqual(found, [
            AllowedApp(bundleID: "com.test.alpha", name: "alpha Display"),
            AllowedApp(bundleID: "com.test.beta", name: "Beta"),
            AllowedApp(bundleID: "com.test.zeta", name: "Zeta"),
        ])
    }

    func testBundleWithoutIdentifierIsSkippedAndFileNameIsTheFallbackName() throws {
        let apps = root.appendingPathComponent("Applications", isDirectory: true)
        try makeApp("NoID.app", in: apps, info: ["CFBundleName": "No ID"])
        try makeApp("Plain.app", in: apps, info: ["CFBundleIdentifier": "com.test.plain"])

        XCTAssertEqual(AppCatalog.scan(directories: [apps]), [AllowedApp(bundleID: "com.test.plain", name: "Plain")])
    }

    func testDuplicateBundleIDKeepsTheFirstDirectoryAndMissingDirectoriesAreIgnored() throws {
        let first = root.appendingPathComponent("First", isDirectory: true)
        let second = root.appendingPathComponent("Second", isDirectory: true)
        try makeApp("Notes.app", in: first, info: ["CFBundleIdentifier": "com.test.notes", "CFBundleName": "Notes"])
        try makeApp("Notes Copy.app", in: second, info: ["CFBundleIdentifier": "com.test.notes", "CFBundleName": "Notes Copy"])
        try makeApp("Calendar.app", in: second, info: ["CFBundleIdentifier": "com.test.calendar", "CFBundleName": "Calendar"])
        let missing = root.appendingPathComponent("DoesNotExist", isDirectory: true)

        let found = AppCatalog.scan(directories: [missing, first, second])

        XCTAssertEqual(found, [
            AllowedApp(bundleID: "com.test.calendar", name: "Calendar"),
            AllowedApp(bundleID: "com.test.notes", name: "Notes"),
        ])
    }

    func testDefaultDirectories() {
        let paths = AppCatalog.defaultDirectories().map(\.path)
        XCTAssertEqual(Array(paths.prefix(2)), ["/Applications", "/System/Applications"])
        XCTAssertTrue(paths[2].hasSuffix("/Applications"))
        XCTAssertEqual(paths.count, 3)
    }

    func testFilterDropsExcludedAppsAndMatchesQueryCaseInsensitively() {
        let apps = [
            AllowedApp(bundleID: "com.google.Chrome", name: "Google Chrome"),
            AllowedApp(bundleID: "com.apple.Notes", name: "Notes"),
            AllowedApp(bundleID: "com.microsoft.VSCode", name: "Visual Studio Code"),
        ]
        let excluded: Set<String> = ["com.google.Chrome", "com.apple.finder"]

        XCTAssertEqual(AppCatalog.filter(apps, query: "", excluding: excluded).map(\.name),
                       ["Notes", "Visual Studio Code"])
        XCTAssertEqual(AppCatalog.filter(apps, query: " studio ", excluding: excluded).map(\.name),
                       ["Visual Studio Code"])
        XCTAssertEqual(AppCatalog.filter(apps, query: "chrome", excluding: excluded), [])
    }
}
```

- [ ] **Step 7: Run the AppCatalog tests and watch them fail**

Run from the repo root:

```bash
cd Tofu && xcodegen generate && xcodebuild -project Tofu.xcodeproj -scheme Tofu -destination 'platform=macOS' test -only-testing:TofuTests/AppCatalogTests 2>&1 | tail -30
```

Expected: `error: cannot find 'AppCatalog' in scope`, then `** TEST FAILED **`.

- [ ] **Step 8: Implement AppCatalog**

Create `Tofu/Tofu/System/AppCatalog.swift`. It reads each bundle with `Bundle(url:)`. The name is `CFBundleDisplayName`, then `CFBundleName`, then the file name. Directory listings are sorted by file name, so "first found wins" is deterministic.

```swift
import Foundation

/// Finds installed apps for AppPickerView by reading `.app` bundles on disk.
enum AppCatalog {
    /// /Applications, /System/Applications and ~/Applications.
    static func defaultDirectories() -> [URL] {
        [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true),
        ]
    }

    /// Every `.app` directly inside each directory, plus one level of plain subfolders
    /// (e.g. /Applications/Utilities). Bundles without a CFBundleIdentifier are skipped.
    /// Deduplicated by bundle ID (first found wins); sorted case-insensitively by name.
    /// Missing directories are ignored.
    static func scan(directories: [URL]) -> [AllowedApp] {
        var seen = Set<String>()
        var apps: [AllowedApp] = []
        for directory in directories {
            for bundleURL in appBundles(in: directory) {
                guard let app = app(at: bundleURL), seen.insert(app.bundleID).inserted else { continue }
                apps.append(app)
            }
        }
        return apps.sorted { lhs, rhs in
            let order = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            return order == .orderedSame ? lhs.bundleID < rhs.bundleID : order == .orderedAscending
        }
    }

    /// Bundle ID plus display name (CFBundleDisplayName, else CFBundleName, else the file name).
    static func app(at bundleURL: URL) -> AllowedApp? {
        guard let bundle = Bundle(url: bundleURL),
              let bundleID = bundle.bundleIdentifier, !bundleID.isEmpty else { return nil }
        let fileName = bundleURL.deletingPathExtension().lastPathComponent
        let name = [
            bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
            bundle.object(forInfoDictionaryKey: "CFBundleName") as? String,
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first { !$0.isEmpty } ?? fileName
        return AllowedApp(bundleID: bundleID, name: name)
    }

    /// Picker rows: drops `excluded` bundle IDs, then keeps names containing `query` (case-insensitive).
    static func filter(_ apps: [AllowedApp], query: String, excluding excluded: Set<String>) -> [AllowedApp] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return apps.filter { app in
            !excluded.contains(app.bundleID) && (needle.isEmpty || app.name.localizedCaseInsensitiveContains(needle))
        }
    }

    private static func appBundles(in directory: URL) -> [URL] {
        var bundles: [URL] = []
        for entry in contents(of: directory) {
            if entry.pathExtension == "app" {
                bundles.append(entry)
            } else if isDirectory(entry) {
                bundles += contents(of: entry).filter { $0.pathExtension == "app" }
            }
        }
        return bundles
    }

    private static func contents(of directory: URL) -> [URL] {
        let entries = try? FileManager.default.contentsOfDirectory(at: directory,
                                                                   includingPropertiesForKeys: [.isDirectoryKey],
                                                                   options: [.skipsHiddenFiles])
        return (entries ?? []).sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }
}
```

- [ ] **Step 9: Run the AppCatalog tests and watch them pass**

Run from the repo root:

```bash
cd Tofu && xcodegen generate && xcodebuild -project Tofu.xcodeproj -scheme Tofu -destination 'platform=macOS' test -only-testing:TofuTests/AppCatalogTests 2>&1 | tail -30
```

Expected: `Executed 5 tests, with 0 failures (0 unexpected)` and `** TEST SUCCEEDED **`.

- [ ] **Step 10: Commit AppCatalog**

```bash
cd "$(git rev-parse --show-toplevel)" && git add Tofu/Tofu/System/AppCatalog.swift Tofu/TofuTests/AppCatalogTests.swift Tofu/Tofu.xcodeproj && git commit -F - <<'EOF'
Add AppCatalog to list installed apps for the app picker

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

- [ ] **Step 11: Create Theme and PresetThumbnail**

Create `Tofu/Tofu/UI/Theme.swift`. Its names and values are binding: later tasks use them as written.

```swift
import AppKit
import SwiftUI

/// Monochrome design tokens (spec §11): grays only, no accent color.
enum Theme {
    static let radius: CGFloat = 10
    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 40
    }
    /// Five grays from strongest to lightest, for stacked chart series.
    static let grays: [Color] = [
        Color.primary,
        Color.primary.opacity(0.7),
        Color.primary.opacity(0.5),
        Color.primary.opacity(0.32),
        Color.primary.opacity(0.18),
    ]
    static func gray(at index: Int) -> Color { grays[index % grays.count] }
    static func timerFont(size: CGFloat) -> Font {
        .system(size: size, weight: .thin, design: .monospaced).monospacedDigit()
    }
    static let titleFont = Font.system(size: 34, weight: .semibold)
    static let captionFont = Font.system(size: 11, weight: .medium).smallCaps()
}

/// Solid fill in the label color (black in light mode, white in dark) with inverted text.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(Color(nsColor: .windowBackgroundColor))
            .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Color.primary))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Rectangle())
    }
}

/// Outlined with a 1 pt border in the label color.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, Theme.Space.m)
            .frame(minHeight: 32)
            .foregroundStyle(Color.primary)
            .background(RoundedRectangle(cornerRadius: Theme.radius).stroke(Color.primary, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
    }
}

/// Small-caps title over a large number, in a hairline-bordered box.
struct StatCard: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(title).font(Theme.captionFont).foregroundStyle(.secondary)
            Text(value).font(.system(size: 22, weight: .semibold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Space.m)
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Color.primary.opacity(0.15), lineWidth: 1))
    }
}
```

Create `Tofu/Tofu/UI/PresetThumbnail.swift`. The zones come from `LayoutEngine`, so the picture always matches the real tiling:
- Chrome zones are outlined.
- The app zone is filled.
- `split` and `full` show a small bar at the top center for the mini timer.

```swift
import SwiftUI

/// Small diagram of a layout preset: Chrome zones outlined, the app zone filled, and a mini-timer
/// bar at the top for presets without an app zone. Zones come from `LayoutEngine`, so the picture
/// always matches the real tiling.
struct PresetThumbnail: View {
    let preset: LayoutPreset

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            if size.width > 12 && size.height > 12 {
                let layout = LayoutEngine.layout(preset, in: CGRect(origin: .zero, size: size))
                ZStack {
                    ForEach(Array(layout.chromeFrames.enumerated()), id: \.offset) { _, frame in
                        zone(frame).stroke(Color.primary, lineWidth: 1)
                    }
                    if let appFrame = layout.appFrame {
                        zone(appFrame).fill(Color.primary.opacity(0.85))
                    }
                    if !preset.appHasZone {
                        Capsule()
                            .fill(Color.primary)
                            .frame(width: size.width * 0.24, height: max(3, size.height * 0.06))
                            .position(x: size.width / 2, y: max(5, size.height * 0.1))
                    }
                }
                .frame(width: size.width, height: size.height)
            }
        }
        .aspectRatio(16.0 / 10.0, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel(Text("\(preset.title) layout"))
    }

    /// A zone inset by 1.5 pt so neighbouring zones show a gap.
    private func zone(_ frame: CGRect) -> some Shape {
        let inset = frame.insetBy(dx: 1.5, dy: 1.5)
        return RoundedRectangle(cornerRadius: 2).path(in: inset)
    }
}
```

- [ ] **Step 12: Create the placeholder screens**

These four files are complete and compile. Each is replaced, whole file, by the task named in its header comment.

Create `Tofu/Tofu/UI/StatsView.swift` (replaced in Task 16):

```swift
import SwiftUI

// PLACEHOLDER: Task 16 replaces this whole file with the real StatsView and SubjectStatsSection.

/// Stats screen (placeholder until Task 16).
struct StatsView: View {
    let model: AppModel

    var body: some View {
        Text("Stats arrive in Task 16")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Cards + 14-day mini chart filtered to one subject (placeholder until Task 16).
struct SubjectStatsSection: View {
    let model: AppModel
    let subjectID: UUID

    var body: some View {
        Text("Stats arrive in Task 16")
            .foregroundStyle(.secondary)
    }
}
```

Create `Tofu/Tofu/UI/SettingsView.swift` (replaced in Task 15):

```swift
import SwiftUI

// PLACEHOLDER: Task 15 replaces this whole file with the real SettingsView.

/// Settings screen (placeholder until Task 15).
struct SettingsView: View {
    let model: AppModel

    var body: some View {
        Text("Settings arrive in Task 15")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

Create `Tofu/Tofu/UI/LockedView.swift` (replaced in Task 14):

```swift
import SwiftUI

// PLACEHOLDER: Task 14 replaces this whole file with the real giant-timer screen.

/// Minimal locked screen: subject, timer and an End button (placeholder until Task 14).
struct LockedView: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: Theme.Space.l) {
            Text(model.engine.subject?.name ?? "")
                .font(Theme.captionFont)
                .foregroundStyle(.secondary)
            Text(TimeFormat.clock(model.engine.remaining ?? model.engine.elapsed))
                .font(Theme.timerFont(size: 96))
            Button("End") {
                Task { await model.engine.finish() }
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

Create `Tofu/Tofu/UI/MainWindowPresenter.swift` (replaced in Task 14):

```swift
import AppKit

// PLACEHOLDER: Task 14 replaces this whole file with the real window handling and mini timer.

/// Live implementation of WindowPresenting. For now it does nothing: the main window stays where it is
/// and RootView swaps to LockedView while a session runs.
@MainActor final class MainWindowPresenter: WindowPresenting {
    private weak var model: AppModel?

    init(model: AppModel) {
        self.model = model
    }

    func enterLocked(appFrame: CGRect?) {}

    func exitLocked() {}
}
```

- [ ] **Step 13: Build**

Run from the repo root:

```bash
cd Tofu && xcodegen generate && xcodebuild -project Tofu.xcodeproj -scheme Tofu -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 14: Commit Theme, thumbnail and placeholders**

```bash
cd "$(git rev-parse --show-toplevel)" && git add Tofu/Tofu/UI/Theme.swift Tofu/Tofu/UI/PresetThumbnail.swift Tofu/Tofu/UI/StatsView.swift Tofu/Tofu/UI/SettingsView.swift Tofu/Tofu/UI/LockedView.swift Tofu/Tofu/UI/MainWindowPresenter.swift Tofu/Tofu.xcodeproj && git commit -F - <<'EOF'
Add monochrome Theme, preset thumbnails and placeholder screens

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

- [ ] **Step 15: Write the failing LockInOption tests**

Create `Tofu/TofuTests/LockInOptionTests.swift`:

```swift
import XCTest
@testable import Tofu

final class LockInOptionTests: XCTestCase {
    func testOptionsInDisplayOrder() {
        XCTAssertEqual(LockInOption.allCases.map(\.title), ["Open-ended", "25 min", "50 min", "90 min", "Custom"])
    }

    func testFixedOptionsMapToModes() {
        XCTAssertEqual(LockInOption.openEnded.mode(customMinutes: 45), .open)
        XCTAssertEqual(LockInOption.minutes25.mode(customMinutes: 45), .goal(minutes: 25))
        XCTAssertEqual(LockInOption.minutes50.mode(customMinutes: 45), .goal(minutes: 50))
        XCTAssertEqual(LockInOption.minutes90.mode(customMinutes: 45), .goal(minutes: 90))
    }

    func testCustomUsesTheStepperValueClampedToItsRange() {
        XCTAssertEqual(LockInOption.customRange, 5...240)
        XCTAssertEqual(LockInOption.custom.mode(customMinutes: 45), .goal(minutes: 45))
        XCTAssertEqual(LockInOption.custom.mode(customMinutes: 1), .goal(minutes: 5))
        XCTAssertEqual(LockInOption.custom.mode(customMinutes: 500), .goal(minutes: 240))
    }
}
```

- [ ] **Step 16: Run the LockInOption tests and watch them fail**

Run from the repo root:

```bash
cd Tofu && xcodegen generate && xcodebuild -project Tofu.xcodeproj -scheme Tofu -destination 'platform=macOS' test -only-testing:TofuTests/LockInOptionTests 2>&1 | tail -30
```

Expected: `error: cannot find 'LockInOption' in scope`, then `** TEST FAILED **`.

- [ ] **Step 17: Create LockInSheet (with LockInOption)**

Create `Tofu/Tofu/UI/LockInSheet.swift`. The sheet offers Open-ended, 25, 50, 90 or Custom (a stepper from 5 to 240 in steps of 5). It shows the always-allowed note, the Discord note and, for goals, the give-up note. **LOCK IN** dismisses the sheet first and then starts the session in a `Task`, so the sheet is gone before the window is moved.

```swift
import SwiftUI

/// The session lengths offered when locking in.
enum LockInOption: Hashable, CaseIterable, Identifiable {
    case openEnded, minutes25, minutes50, minutes90, custom

    /// Stepper range for `custom`, in minutes (step 5).
    static let customRange = 5...240

    var id: Self { self }

    var title: String {
        switch self {
        case .openEnded: return "Open-ended"
        case .minutes25: return "25 min"
        case .minutes50: return "50 min"
        case .minutes90: return "90 min"
        case .custom: return "Custom"
        }
    }

    /// Session mode for this option; `customMinutes` is clamped to `customRange`.
    func mode(customMinutes: Int) -> SessionMode {
        switch self {
        case .openEnded: return .open
        case .minutes25: return .goal(minutes: 25)
        case .minutes50: return .goal(minutes: 50)
        case .minutes90: return .goal(minutes: 90)
        case .custom:
            let clamped = min(max(customMinutes, Self.customRange.lowerBound), Self.customRange.upperBound)
            return .goal(minutes: clamped)
        }
    }
}

/// Mode choice before locking in: open-ended or a goal, then LOCK IN.
struct LockInSheet: View {
    let model: AppModel
    let subject: Subject
    @Environment(\.dismiss) private var dismiss
    @State private var option: LockInOption = .openEnded
    @State private var customMinutes = 45

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text("Lock in").font(Theme.captionFont).foregroundStyle(.secondary)
                Text(subject.name).font(Theme.titleFont).lineLimit(1)
            }

            Picker("Length", selection: $option) {
                ForEach(LockInOption.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if option == .custom {
                Stepper(value: $customMinutes, in: LockInOption.customRange, step: 5) {
                    Text("\(customMinutes) min").monospacedDigit()
                }
            }

            VStack(alignment: .leading, spacing: Theme.Space.s) {
                note("Other apps will be hidden. Google Chrome, Finder\(subject.allowedApps.isEmpty ? "" : " and your allowed apps") stay available.")
                note(model.data.settings.discordEnabled
                     ? "Your Discord servers will see that you locked in."
                     : "Discord announcements are off (turn them on in Settings).")
                if option != .openEnded {
                    note("Ending before the goal means typing the give-up phrase.")
                }
            }

            HStack(spacing: Theme.Space.m) {
                Button("Cancel") { dismiss() }
                    .buttonStyle(SecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    lockIn()
                } label: {
                    Text("LOCK IN").tracking(2)
                }
                .buttonStyle(PrimaryButtonStyle())
                .frame(width: 180)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.Space.xl)
        .frame(width: 480)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Closes the sheet first so the window is free to move, then starts the session.
    private func lockIn() {
        let mode = option.mode(customMinutes: customMinutes)
        let subjectID = subject.id
        let model = model
        dismiss()
        Task { await model.lockIn(subjectID: subjectID, mode: mode) }
    }
}
```

- [ ] **Step 18: Run the LockInOption tests and watch them pass**

Run from the repo root:

```bash
cd Tofu && xcodegen generate && xcodebuild -project Tofu.xcodeproj -scheme Tofu -destination 'platform=macOS' test -only-testing:TofuTests/LockInOptionTests 2>&1 | tail -30
```

Expected: `Executed 3 tests, with 0 failures (0 unexpected)` and `** TEST SUCCEEDED **`.

- [ ] **Step 19: Create AppPickerView (with AppIcon)**

Create `Tofu/Tofu/UI/AppPickerView.swift`:
- `AppCatalog.scan` runs in a detached task, so the sheet opens instantly.
- Chrome, Finder and our own app are never listed, because they are always allowed. A note says so.
- `AppIcon` shows an app's Finder icon in grayscale to keep the UI monochrome. `SubjectEditorView` and `SubjectDetailView` reuse it.

```swift
import AppKit
import SwiftUI

/// Sheet that edits a subject's allowed apps: installed apps with icon, name, search and checkmarks.
struct AppPickerView: View {
    @Binding var selection: [AllowedApp]
    @Environment(\.dismiss) private var dismiss
    @State private var apps: [AllowedApp] = []
    @State private var query = ""
    @State private var isLoading = true

    /// Always allowed during every session, so never offered here.
    private var excluded: Set<String> {
        BlockPolicy.alwaysAllowed.union([Bundle.main.bundleIdentifier ?? "com.tofu.app"])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("Allowed apps").font(.title2.weight(.semibold))
            Text("Google Chrome and Finder are always allowed, so they are not listed.")
                .font(.callout)
                .foregroundStyle(.secondary)
            TextField("Search apps", text: $query)
                .textFieldStyle(.roundedBorder)
            List(AppCatalog.filter(apps, query: query, excluding: excluded)) { app in
                Button {
                    toggle(app)
                } label: {
                    HStack(spacing: Theme.Space.s) {
                        AppIcon(bundleID: app.bundleID).frame(width: 22, height: 22)
                        Text(app.name)
                        Spacer()
                        if isSelected(app) {
                            Image(systemName: "checkmark").fontWeight(.semibold)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .overlay {
                if isLoading {
                    ProgressView()
                }
            }
            HStack {
                Text("\(selection.count) selected").foregroundStyle(.secondary)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(PrimaryButtonStyle())
                    .frame(width: 120)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.Space.l)
        .frame(width: 460, height: 580)
        .task { await load() }
    }

    private func isSelected(_ app: AllowedApp) -> Bool {
        selection.contains { $0.bundleID == app.bundleID }
    }

    private func toggle(_ app: AllowedApp) {
        if isSelected(app) {
            selection.removeAll { $0.bundleID == app.bundleID }
        } else {
            selection.append(app)
        }
    }

    /// Scans the app folders off the main thread.
    private func load() async {
        let found = await Task.detached(priority: .userInitiated) {
            AppCatalog.scan(directories: AppCatalog.defaultDirectories())
        }.value
        apps = found
        isLoading = false
    }
}

/// An installed app's icon in grayscale (the UI stays monochrome), or a placeholder if it is not installed.
struct AppIcon: View {
    let bundleID: String

    var body: some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .saturation(0)
        } else {
            Image(systemName: "app.dashed")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.secondary)
        }
    }
}
```

- [ ] **Step 20: Create SubjectEditorView**

Create `Tofu/Tofu/UI/SubjectEditorView.swift`:
- `sites` always has at least 2 slots (`SubjectValidator.siteSlots`). Switching from Left / Right to Full and back keeps the second site.
- Save is disabled, and dimmed (custom button styles don't dim themselves), while `SubjectValidator.errors` is non-empty. The errors are listed as secondary text next to the buttons.
- Saved sites are full `https://` URLs. Extra domains are saved as normalized hosts.

```swift
import SwiftUI

/// Sheet for creating (`subject == nil`) or editing a subject.
struct SubjectEditorView: View {
    let model: AppModel
    private let original: Subject?
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var preset: LayoutPreset
    /// Always at least 2 slots; only the first `preset.siteCount` are shown and saved.
    @State private var sites: [String]
    @State private var allowedApps: [AllowedApp]
    @State private var extraDomainsText: String
    @State private var isPickingApps = false

    init(model: AppModel, subject: Subject?) {
        self.model = model
        self.original = subject
        _name = State(initialValue: subject?.name ?? "")
        _preset = State(initialValue: subject?.preset ?? .split)
        _sites = State(initialValue: SubjectValidator.siteSlots(subject?.sites ?? []))
        _allowedApps = State(initialValue: subject?.allowedApps ?? [])
        _extraDomainsText = State(initialValue: (subject?.extraDomains ?? []).joined(separator: ", "))
    }

    private var visibleSites: [String] { Array(sites.prefix(preset.siteCount)) }
    private var errors: [String] { SubjectValidator.errors(name: name, sites: visibleSites, preset: preset) }
    private var parsedDomains: [String] { SubjectValidator.parseDomains(extraDomainsText) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    Text(original == nil ? "New subject" : "Edit subject").font(.title2.weight(.semibold))
                    nameSection
                    presetSection
                    sitesSection
                    appsSection
                    domainsSection
                }
                .padding(Theme.Space.l)
            }
            Divider()
            footer.padding(Theme.Space.l)
        }
        .frame(width: 600, height: 680)
        .sheet(isPresented: $isPickingApps) {
            AppPickerView(selection: $allowedApps)
        }
    }

    private var nameSection: some View {
        section("Name") {
            TextField("e.g. CS128", text: $name)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var presetSection: some View {
        section("Layout") {
            HStack(spacing: Theme.Space.m) {
                ForEach(LayoutPreset.allCases) { option in
                    Button {
                        preset = option
                    } label: {
                        VStack(spacing: Theme.Space.s) {
                            PresetThumbnail(preset: option).frame(width: 100)
                            Text(option.title).font(.caption)
                        }
                        .padding(Theme.Space.s)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.radius)
                                .stroke(Color.primary.opacity(preset == option ? 1 : 0.15),
                                        lineWidth: preset == option ? 2 : 1)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(preset == option ? .isSelected : [])
                }
            }
        }
    }

    private var sitesSection: some View {
        section(preset.siteCount == 1 ? "Site" : "Sites") {
            ForEach(0..<preset.siteCount, id: \.self) { index in
                TextField(index == 0 ? "e.g. cs128.org" : "e.g. prairielearn.org", text: $sites[index])
                    .textFieldStyle(.roundedBorder)
            }
            Text(preset.appHasZone
                 ? "Each site opens in its own Chrome window; this app takes the remaining zone."
                 : "Each site opens in its own Chrome window; a mini timer floats on top.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var appsSection: some View {
        section("Allowed apps") {
            if allowedApps.isEmpty {
                Text("None. Only Google Chrome and Finder stay available.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(allowedApps) { app in
                    HStack(spacing: Theme.Space.s) {
                        AppIcon(bundleID: app.bundleID).frame(width: 20, height: 20)
                        Text(app.name)
                        Spacer()
                        Button {
                            allowedApps.removeAll { $0.bundleID == app.bundleID }
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove \(app.name)")
                    }
                }
            }
            Button("Add apps…") { isPickingApps = true }
                .buttonStyle(SecondaryButtonStyle())
        }
    }

    private var domainsSection: some View {
        section("Extra allowed sites") {
            TextField("e.g. piazza.com, stackoverflow.com", text: $extraDomainsText)
                .textFieldStyle(.roundedBorder)
            Text(parsedDomains.isEmpty
                 ? "Comma-separated. Subdomains are included."
                 : "Allows: " + parsedDomains.joined(separator: ", "))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                ForEach(errors, id: \.self) { message in
                    Text(message).font(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(SecondaryButtonStyle())
                .keyboardShortcut(.cancelAction)
            Button("Save") { save() }
                .buttonStyle(PrimaryButtonStyle())
                .frame(width: 120)
                .opacity(errors.isEmpty ? 1 : 0.35)
                .disabled(!errors.isEmpty)
                .keyboardShortcut(.defaultAction)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text(title).font(Theme.captionFont).foregroundStyle(.secondary)
            content()
        }
    }

    private func save() {
        guard errors.isEmpty else { return }
        let subject = Subject(id: original?.id ?? UUID(),
                              name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                              preset: preset,
                              sites: SubjectValidator.sitesForSave(visibleSites, preset: preset),
                              allowedApps: allowedApps,
                              extraDomains: parsedDomains,
                              createdAt: original?.createdAt ?? Date())
        if original == nil {
            model.addSubject(subject)
        } else {
            model.updateSubject(subject)
        }
        dismiss()
    }
}
```

- [ ] **Step 21: Create SubjectDetailView**

Create `Tofu/Tofu/UI/SubjectDetailView.swift`. The **LOCK IN** button is full width and 56 pt tall, with shortcut ⌘↩. It opens `LockInSheet`.

```swift
import SwiftUI

/// One subject: its setup at a glance, the LOCK IN button and its stats.
struct SubjectDetailView: View {
    let model: AppModel
    let subject: Subject
    @State private var isEditing = false
    @State private var isChoosingMode = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                header
                HStack(alignment: .top, spacing: Theme.Space.l) {
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        PresetThumbnail(preset: subject.preset).frame(width: 140)
                        Text(subject.preset.title).font(.callout).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: Theme.Space.m) {
                        sitesBlock
                        appsBlock
                        domainsBlock
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button {
                    isChoosingMode = true
                } label: {
                    Text("LOCK IN")
                        .tracking(3)
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.return, modifiers: .command)
                SubjectStatsSection(model: model, subjectID: subject.id)
            }
            .padding(Theme.Space.xl)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(subject.name)
        .sheet(isPresented: $isEditing) {
            SubjectEditorView(model: model, subject: subject)
        }
        .sheet(isPresented: $isChoosingMode) {
            LockInSheet(model: model, subject: subject)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(subject.name)
                .font(Theme.titleFont)
                .lineLimit(1)
            Spacer()
            Button("Edit") { isEditing = true }
                .buttonStyle(SecondaryButtonStyle())
        }
    }

    private var sitesBlock: some View {
        block(subject.sites.count == 1 ? "Site" : "Sites") {
            ForEach(subject.sites, id: \.self) { site in
                Text(site).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
            }
        }
    }

    private var appsBlock: some View {
        block("Allowed apps") {
            HStack(spacing: Theme.Space.s) {
                ForEach(subject.allowedApps) { app in
                    AppIcon(bundleID: app.bundleID)
                        .frame(width: 28, height: 28)
                        .help(app.name)
                }
                Text(subject.allowedApps.isEmpty ? "Chrome and Finder only" : "+ Chrome and Finder")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var domainsBlock: some View {
        block("Extra allowed sites") {
            Text(subject.extraDomains.isEmpty ? "None" : subject.extraDomains.joined(separator: ", "))
                .foregroundStyle(subject.extraDomains.isEmpty ? .secondary : .primary)
        }
    }

    private func block<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(title).font(Theme.captionFont).foregroundStyle(.secondary)
            content()
        }
    }
}
```

- [ ] **Step 22: Build**

Run from the repo root:

```bash
cd Tofu && xcodegen generate && xcodebuild -project Tofu.xcodeproj -scheme Tofu -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 23: Commit the subject screens**

```bash
cd "$(git rev-parse --show-toplevel)" && git add Tofu/Tofu/UI/LockInSheet.swift Tofu/Tofu/UI/AppPickerView.swift Tofu/Tofu/UI/SubjectEditorView.swift Tofu/Tofu/UI/SubjectDetailView.swift Tofu/TofuTests/LockInOptionTests.swift Tofu/Tofu.xcodeproj && git commit -F - <<'EOF'
Add subject detail, editor, app picker and lock-in sheet

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

- [ ] **Step 24: Create SidebarView and RootView**

Create `Tofu/Tofu/UI/SidebarView.swift`:
- The empty state reads exactly "No subjects yet. Add one to lock in."
- Each row shows the subject's total finished time (`TimeFormat.short`).
- "Add subject" (⌘N) opens the editor.
- Right-click › Delete asks for confirmation. The dialog has no destructive red, to stay monochrome.

```swift
import SwiftUI

/// Subjects (with total time), then Stats and Settings. "+" adds a subject; right-click deletes one.
struct SidebarView: View {
    @Bindable var model: AppModel
    @State private var isAddingSubject = false
    @State private var subjectToDelete: Subject?

    var body: some View {
        List(selection: $model.selection) {
            Section("Subjects") {
                if model.data.subjects.isEmpty {
                    Text("No subjects yet. Add one to lock in.")
                        .foregroundStyle(.secondary)
                        .selectionDisabled()
                } else {
                    ForEach(model.data.subjects) { subject in
                        HStack {
                            Text(subject.name).lineLimit(1)
                            Spacer()
                            Text(TimeFormat.short(totalTime(of: subject.id)))
                                .font(.callout)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .tag(SidebarItem.subject(subject.id))
                        .contextMenu {
                            Button("Delete “\(subject.name)”…") { subjectToDelete = subject }
                        }
                    }
                }
            }
            Section {
                Label("Stats", systemImage: "chart.bar").tag(SidebarItem.stats)
                Label("Settings", systemImage: "gearshape").tag(SidebarItem.settings)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        .safeAreaInset(edge: .bottom) {
            Button {
                isAddingSubject = true
            } label: {
                Label("Add subject", systemImage: "plus").frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle())
            .keyboardShortcut("n", modifiers: .command)
            .help("Add subject (⌘N)")
            .padding(Theme.Space.m)
        }
        .sheet(isPresented: $isAddingSubject) {
            SubjectEditorView(model: model, subject: nil)
        }
        .confirmationDialog(
            "Delete “\(subjectToDelete?.name ?? "")”?",
            isPresented: Binding(get: { subjectToDelete != nil },
                                 set: { if !$0 { subjectToDelete = nil } }),
            titleVisibility: .visible,
            presenting: subjectToDelete
        ) { subject in
            Button("Delete") { model.deleteSubject(id: subject.id) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Its past sessions stay in your stats.")
        }
    }

    /// Total time of the subject's finished sessions.
    private func totalTime(of subjectID: UUID) -> TimeInterval {
        model.data.sessions
            .filter { $0.subjectID == subjectID && $0.end != nil }
            .reduce(0) { $0 + $1.duration }
    }
}
```

Create `Tofu/Tofu/UI/RootView.swift`. While `engine.isLocked`, it shows `LockedView` in place of the split view. `.id(subject.id)` resets the detail's sheet state when the selection changes.

```swift
import SwiftUI

/// NavigationSplitView (sidebar + detail). When model.engine.isLocked shows LockedView(model:) full-window instead.
struct RootView: View {
    let model: AppModel

    var body: some View {
        Group {
            if model.engine.isLocked {
                LockedView(model: model)
            } else {
                NavigationSplitView {
                    SidebarView(model: model)
                } detail: {
                    detail
                }
            }
        }
        .frame(minWidth: 820, minHeight: 560)
    }

    @ViewBuilder private var detail: some View {
        switch model.selection {
        case .subject(let id):
            if let subject = model.subject(id: id) {
                SubjectDetailView(model: model, subject: subject)
                    .id(subject.id)
            } else {
                emptyState
            }
        case .stats:
            StatsView(model: model)
        case .settings:
            SettingsView(model: model)
        case nil:
            emptyState
        }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Space.s) {
            Text("Pick a subject to lock in").font(.title3.weight(.semibold))
            Text(model.data.subjects.isEmpty ? "Add one with “Add subject” in the sidebar." : "Or open Stats and Settings.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

- [ ] **Step 25: Create AppDelegate and replace the app entry point**

Create `Tofu/Tofu/App/AppDelegate.swift`:
- The model is created lazily by the first `RootView` render or by `applicationDidFinishLaunching`, whichever comes first.
- Under tests, nothing is created. The hosted test run only shows "Running tests".
- On quit, `terminateNow()` unhides the apps we hid and records the session as `interrupted`, with no Discord post (Review Focus 3, live side).

```swift
import AppKit

/// Owns the AppModel, connects the live window presenter, and ends a running session on quit.
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    static var isRunningTests: Bool { ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil }

    private var storedModel: AppModel?
    private var presenter: MainWindowPresenter?

    /// Created lazily on first access (never during tests).
    var model: AppModel {
        if let storedModel { return storedModel }
        let created = AppModel()
        storedModel = created
        return created
    }

    /// Creates MainWindowPresenter(model:), retains it, assigns model.engine.presenter. No-op under tests.
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isRunningTests else { return }
        let presenter = MainWindowPresenter(model: model)
        self.presenter = presenter
        model.engine.presenter = presenter
    }

    /// model.engine.terminateNow() then model.save(). No-op under tests.
    /// Unhides the apps we hid and records the session as interrupted (no Discord post).
    func applicationWillTerminate(_ notification: Notification) {
        guard !Self.isRunningTests, let storedModel else { return }
        storedModel.engine.terminateNow()
        storedModel.save()
    }
}
```

Replace the whole contents of `Tofu/Tofu/App/TofuApp.swift` with the final version. `CommandGroup(replacing: .newItem) {}` removes File › New Window, so there is only ever one main window.

```swift
import SwiftUI

/// App entry point: a single main window ("New Window" is disabled). The AppDelegate owns the model.
@main
struct TofuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup("Tofu", id: "main") {
            if AppDelegate.isRunningTests {
                Text("Running tests")
            } else {
                RootView(model: appDelegate.model)
            }
        }
        .defaultSize(width: 1100, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
```

- [ ] **Step 26: Build and run the full suite**

Run from the repo root:

```bash
cd Tofu && xcodegen generate && xcodebuild -project Tofu.xcodeproj -scheme Tofu -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

```bash
cd Tofu && xcodebuild -project Tofu.xcodeproj -scheme Tofu -destination 'platform=macOS' test 2>&1 | tail -30
```

Expected: `** TEST SUCCEEDED **`, with every test from Tasks 1–13 passing. While the tests run, the test host window shows only "Running tests". No store is loaded and nothing is hidden.

- [ ] **Step 27: Manual verification**

Launch the built app from the repo root:

```bash
cd Tofu && open "$(xcodebuild -project Tofu.xcodeproj -scheme Tofu -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2; exit}')/Tofu.app"
```

You can also press Run in Xcode. Do **not** click the final **LOCK IN** yet. Lock-in hides your other apps, and the real locked window handling arrives in Task 14. If you click it by accident, click **End** in the window to bring the hidden apps back.

Check each item:

1. **First launch.** On a fresh `~/Library/Application Support/Tofu/store.json`, one window titled "Tofu" opens at about 1100×720.
   - The sidebar shows the "Subjects" header, the text "No subjects yet. Add one to lock in.", then **Stats** and **Settings**, and an outlined **Add subject** button at the bottom.
   - The detail reads "Pick a subject to lock in".
   - The **File** menu has no "New Window" item.
   - **Stats** shows "Stats arrive in Task 16". **Settings** shows "Settings arrive in Task 15".
2. **New subject sheet.** Click **Add subject** (or press ⌘N). The "New subject" sheet opens.
   - **Left / Right** has the thick border.
   - Two site fields are shown.
   - **Save** is dimmed. The footer lists "Name is required" and "Add 2 sites for this layout".
3. **Validation.** Type `CS128` as the name. Type `cs128.org` in the first site and `not a url` in the second. The footer now shows only "Site 2 is not a valid URL". Replace the second site with `prairielearn.org`. The footer becomes empty and **Save** is enabled.
4. **Layout switching.** Click the **Full** thumbnail. One site field remains, showing `cs128.org`. Click **Left / Right** again. The second field shows `prairielearn.org` again.
5. **Extra domains.** Type `Piazza.com, https://www.stackoverflow.com/questions` under "Extra allowed sites". The caption reads "Allows: piazza.com, stackoverflow.com".
6. **App picker.** Click **Add apps…**.
   - The picker lists installed apps alphabetically, with grayscale icons.
   - Google Chrome and Finder are absent, and a note explains why.
   - Type `term`; the list narrows to names containing "term", including Terminal. Click **Terminal**: a checkmark appears and the footer says "1 selected". Click **Done**.
   - The editor lists Terminal with an ✕ button.
7. **Save.** Click **Save**. The sheet closes, and the sidebar shows **CS128** with `0m`, selected. The detail shows:
   - "CS128" in the large title font
   - the Left / Right thumbnail: two outlined boxes and a small bar at the top
   - Sites `https://cs128.org` and `https://prairielearn.org`
   - the Terminal icon and "+ Chrome and Finder"
   - "piazza.com, stackoverflow.com"
   - a full-width black **LOCK IN** button (white in dark mode), about 56 pt tall
   - "Stats arrive in Task 16" below it
8. **Edit.** Click **Edit**. The editor opens with every field filled in, including Terminal. Click **Cancel**; nothing changes.
9. **Lock-in sheet.** Click **LOCK IN** on the detail page. The sheet shows:
   - "Lock in" in small caps, then "CS128"
   - a segmented control: Open-ended · 25 min · 50 min · 90 min · Custom
   - the notes "Other apps will be hidden. Google Chrome, Finder and your allowed apps stay available." and "Discord announcements are off (turn them on in Settings)."

   Select **Custom**: a stepper shows "45 min", and clicking + makes it "50 min". The note "Ending before the goal means typing the give-up phrase." appears. Click **Cancel**. The sheet closes and no app is hidden.
10. **Delete dialog.** Right-click **CS128** › **Delete “CS128”…**. A dialog asks "Delete “CS128”?" with "Its past sessions stay in your stats." Click **Cancel**; CS128 stays.
11. **Persistence.** Quit with ⌘Q and launch again with the same `open` command. CS128 is still listed and selected. `grep -c 'cs128\.org' ~/Library/Application\ Support/Tofu/store.json` prints `1`. JSONEncoder escapes slashes, so the file stores the site as `https:\/\/cs128.org`.
12. **Dark mode.** Switch to dark mode in System Settings › Appearance. The background turns black and the text white. **LOCK IN** becomes a white fill with black text, and the thumbnails are white outlines. No colored accents appear anywhere.

- [ ] **Step 28: Commit the shell**

```bash
cd "$(git rev-parse --show-toplevel)" && git add Tofu/Tofu/UI/SidebarView.swift Tofu/Tofu/UI/RootView.swift Tofu/Tofu/App/AppDelegate.swift Tofu/Tofu/App/TofuApp.swift Tofu/Tofu.xcodeproj && git commit -F - <<'EOF'
Add main window shell: sidebar, root view, app delegate and final app entry

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

Expected: `git status --short` prints nothing.

### Task 14: Locked UI (LockedView, GiveUpSheet, MiniTimerPanel, MainWindowPresenter)

This task replaces the two placeholders from Task 13 with the real locked UI. Its last steps run the whole lock-in path on a real Mac, which is where Tasks 3, 7, 8, 9, 10, 12, 13 and 14 are first checked together.

What each piece does:

- **`LockedView`** fills the main window while locked. It has a black/white background (`Color.lockBackground`), the subject name in `Theme.captionFont`, and a giant `TimeFormat.clock(engine.remaining ?? engine.elapsed)`.
  - The timer font size is `min(width / 5, height * 0.42)` of the space a `GeometryReader` gives it.
  - In goal mode a 2 pt progress line and a `goal 25m` caption sit under the timer.
  - Under that are the counters `3 apps blocked · 2 tabs closed` and an outlined **End** button. End opens `GiveUpSheet` when `engine.needsGiveUpPhrase` is true. Otherwise it asks "End this session?" and then calls `engine.finish()`.
  - The view re-renders every tick because it reads `engine.now` (through `elapsed`/`remaining`).
- **`GiveUpSheet`** shows "Ending early will be posted to Discord." and the exact phrase in monospace, plus a text field. **Bail** is enabled only when `engine.phraseMatches(_:template:)` is true. Bail closes the sheet and calls `engine.bail()`; **Cancel** returns to the session.
- **`MiniTimerPanel`** is a borderless, non-activating `NSPanel` at `.floating` level, 240×64 pt, top-center, 8 pt below the menu bar. It sets `hidesOnDeactivate = false` because our app is inactive while Chrome is in front.
  - Its SwiftUI content (`MiniTimerView`) is only visual. A transparent `ClickDragView` sits on top: a click (body or ✕) calls `onOpen`, and a drag of 3 pt or more moves the panel instead.
  - Handling the mouse in AppKit keeps a drag from also counting as a click. `acceptsFirstMouse` makes the first click work while the app is inactive. So `isMovableByWindowBackground` stays off; the overlay does the moving.
- **`MainWindowPresenter`** is the live `WindowPresenting`.
  - It finds the main window with `NSApp.windows.first(where: { !($0 is NSPanel) && $0.sheetParent == nil && $0.canBecomeMain })` and saves its frame.
  - With an app zone, it moves the window there, animated, and brings it to the front. Without one, it orders the window out and shows the mini timer.
  - `showMainWindow()` (mini timer click) shows the window at 900×600, centered.
  - `exitLocked()` closes the panel, restores the saved frame and brings the app to the front.
  - **It keeps a weak reference to the window it found.** An ordered-out window is invisible, and an invisible `NSWindow` reports `canBecomeMain == false` (checked on macOS 14+). So the lookup alone cannot find the window again after `orderOut`.
  - **It applies the app-zone frame a second time 0.3 s later.** `SessionEngine` calls `enterLocked` before SwiftUI has swapped `RootView` to `LockedView`, so the old content's minimum size could clamp the first `setFrame`.

All the math lives in two pure enums, `MiniTimerLayout` and `LockedLayout`, and is unit-tested.

**Files:**
- Create: `Tofu/Tofu/UI/GiveUpSheet.swift`
- Create: `Tofu/Tofu/UI/MiniTimerPanel.swift`
- Modify (replace the whole Task 13 placeholder): `Tofu/Tofu/UI/LockedView.swift`
- Modify (replace the whole Task 13 placeholder): `Tofu/Tofu/UI/MainWindowPresenter.swift`
- Test: `Tofu/TofuTests/MiniTimerLayoutTests.swift`
- Test: `Tofu/TofuTests/LockedLayoutTests.swift`
- Modify (regenerated by `xcodegen generate`): `Tofu/Tofu.xcodeproj`

**Interfaces:**
- Consumes:
  - Task 2: `struct Session` (`subjectName: String`, `mode: SessionMode`, `blockedAttempts: Int`, `closedTabs: Int`); `enum SessionMode` with `var goalSeconds: TimeInterval?`; `struct AppSettings` with `var giveUpTemplate: String`; `struct StoreData` with `var settings: AppSettings`
  - Task 3: `@MainActor static func ScreenGeometry.mainVisibleFrame() -> CGRect?`
  - Task 5: `static func TimeFormat.clock(_ seconds: TimeInterval) -> String`; `static func TimeFormat.short(_ seconds: TimeInterval) -> String`
  - Task 10: `@MainActor protocol WindowPresenting: AnyObject { func enterLocked(appFrame: CGRect?); func exitLocked() }`; `@Observable @MainActor final class SessionEngine` with `private(set) var session: Session?`, `var isLocked: Bool`, `var elapsed: TimeInterval`, `var remaining: TimeInterval?`, `var needsGiveUpPhrase: Bool`, `func giveUpPhrase(template: String) -> String`, `func phraseMatches(_ typed: String, template: String) -> Bool`, `func finish() async`, `func bail() async`, `weak var presenter: WindowPresenting?`
  - Task 12: `@Observable @MainActor final class AppModel` with `var data: StoreData` and `let engine: SessionEngine`
  - Task 13: `enum Theme` (`radius`, `Space.xs/s/m/l/xl`, `captionFont`, `timerFont(size:)`); `struct SecondaryButtonStyle: ButtonStyle`. `AppDelegate.applicationDidFinishLaunching` creates and retains `MainWindowPresenter(model:)` and assigns `model.engine.presenter`. `RootView` shows `LockedView(model:)` full-window while `model.engine.isLocked`. The placeholder files `UI/LockedView.swift` and `UI/MainWindowPresenter.swift` are replaced here.
- Produces:
  - `struct LockedView: View { let model: AppModel }` (binding, unchanged from the Task 13 placeholder)
  - `@MainActor final class MainWindowPresenter: WindowPresenting { init(model: AppModel); func enterLocked(appFrame: CGRect?); func exitLocked(); func showMainWindow() }` (binding; `showMainWindow()` is new in this task)
  - `struct GiveUpSheet: View { let model: AppModel }`
  - `enum MiniTimerLayout { static let panelSize: CGSize /* 240x64 */; static let topMargin: CGFloat /* 8 */; static let dragThreshold: CGFloat /* 3 */; static func frame(size: CGSize, visible: CGRect, topMargin: CGFloat = MiniTimerLayout.topMargin) -> CGRect; static func isDrag(from start: CGPoint, to current: CGPoint) -> Bool; static func draggedOrigin(_ origin: CGPoint, from mouseStart: CGPoint, to mouse: CGPoint) -> CGPoint }`
  - `struct MiniTimerView: View { let engine: SessionEngine }`
  - `@MainActor final class MiniTimerPanel: NSPanel { init(engine: SessionEngine, onOpen: @escaping () -> Void); func show() }`
  - `enum LockedLayout { static let windowSize: CGSize /* 900x600 */; static func timerFontSize(for size: CGSize) -> CGFloat; static func progress(elapsed: TimeInterval, goal: TimeInterval) -> Double; static func countersText(blocked: Int, tabs: Int) -> String; static func goalCaption(goalSeconds: TimeInterval) -> String; static func centeredFrame(size: CGSize, in visible: CGRect) -> CGRect }`
  - `extension Color { static let lockBackground: Color }`: white in light mode, black in dark mode

- [ ] **Step 1: Write the failing MiniTimerLayout tests**

Create `Tofu/TofuTests/MiniTimerLayoutTests.swift`:

```swift
import XCTest
@testable import Tofu

final class MiniTimerLayoutTests: XCTestCase {
    private let size = CGSize(width: 240, height: 64)

    func testPanelSizeAndMarginMatchTheSpec() {
        XCTAssertEqual(MiniTimerLayout.panelSize, CGSize(width: 240, height: 64))
        XCTAssertEqual(MiniTimerLayout.topMargin, 8)
    }

    func testFrameIsCenteredHorizontallyEightPointsBelowTheTop() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)
        XCTAssertEqual(MiniTimerLayout.frame(size: size, visible: visible),
                       CGRect(x: 600, y: 803, width: 240, height: 64))
    }

    func testFrameFollowsTheVisibleFrameOrigin() {
        // Dock on the left and a bottom inset: the panel is centered within the visible frame, not the screen.
        let visible = CGRect(x: 100, y: 50, width: 1200, height: 800)
        XCTAssertEqual(MiniTimerLayout.frame(size: size, visible: visible),
                       CGRect(x: 580, y: 778, width: 240, height: 64))
    }

    func testCustomTopMargin() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)
        XCTAssertEqual(MiniTimerLayout.frame(size: size, visible: visible, topMargin: 20),
                       CGRect(x: 600, y: 791, width: 240, height: 64))
    }

    func testOddWidthRoundsXDownToAWholePoint() {
        let visible = CGRect(x: 0, y: 0, width: 1001, height: 700)
        XCTAssertEqual(MiniTimerLayout.frame(size: size, visible: visible),
                       CGRect(x: 380, y: 628, width: 240, height: 64))
    }

    func testPanelWiderThanTheScreenIsPinnedToTheLeftEdge() {
        let visible = CGRect(x: 30, y: 0, width: 200, height: 400)
        XCTAssertEqual(MiniTimerLayout.frame(size: size, visible: visible),
                       CGRect(x: 30, y: 328, width: 240, height: 64))
    }

    func testSecondaryScreenAboveThePrimary() {
        // A screen stacked above the primary has a positive y origin in Cocoa coordinates.
        let visible = CGRect(x: -200, y: 900, width: 1920, height: 1055)
        XCTAssertEqual(MiniTimerLayout.frame(size: size, visible: visible),
                       CGRect(x: 640, y: 1883, width: 240, height: 64))
    }

    func testSmallMovementIsAClickNotADrag() {
        XCTAssertFalse(MiniTimerLayout.isDrag(from: .zero, to: .zero))
        XCTAssertFalse(MiniTimerLayout.isDrag(from: .zero, to: CGPoint(x: 2, y: 2)))
        XCTAssertFalse(MiniTimerLayout.isDrag(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 8, y: 11)))
    }

    func testMovementAtOrBeyondThresholdIsADrag() {
        XCTAssertTrue(MiniTimerLayout.isDrag(from: .zero, to: CGPoint(x: 3, y: 0)))
        XCTAssertTrue(MiniTimerLayout.isDrag(from: .zero, to: CGPoint(x: -2, y: -3)))
        XCTAssertTrue(MiniTimerLayout.isDrag(from: CGPoint(x: 500, y: 500), to: CGPoint(x: 400, y: 620)))
    }

    func testDraggedOriginMovesByThePointerDelta() {
        let origin = CGPoint(x: 600, y: 803)
        XCTAssertEqual(MiniTimerLayout.draggedOrigin(origin, from: CGPoint(x: 700, y: 830), to: CGPoint(x: 650, y: 800)),
                       CGPoint(x: 550, y: 773))
        XCTAssertEqual(MiniTimerLayout.draggedOrigin(origin, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 10, y: 10)),
                       origin)
    }
}
```

- [ ] **Step 2: Write the failing LockedLayout tests**

Create `Tofu/TofuTests/LockedLayoutTests.swift`:

```swift
import XCTest
@testable import Tofu

final class LockedLayoutTests: XCTestCase {
    func testWindowSizeIs900By600() {
        XCTAssertEqual(LockedLayout.windowSize, CGSize(width: 900, height: 600))
    }

    func testTimerFontIsLimitedByWidthInATallZone() {
        // Thirds app zone on a 1440x875 visible frame: 480 wide.
        XCTAssertEqual(LockedLayout.timerFontSize(for: CGSize(width: 480, height: 700)), 96)
    }

    func testTimerFontIsLimitedByHeightInAWideZone() {
        XCTAssertEqual(LockedLayout.timerFontSize(for: CGSize(width: 900, height: 300)), 126, accuracy: 0.0001)
    }

    func testTimerFontUsesTheSmallerOfBothLimits() {
        XCTAssertEqual(LockedLayout.timerFontSize(for: CGSize(width: 1000, height: 600)), 200)
    }

    func testTimerFontNeverDropsBelowOnePoint() {
        XCTAssertEqual(LockedLayout.timerFontSize(for: .zero), 1)
        XCTAssertEqual(LockedLayout.timerFontSize(for: CGSize(width: -50, height: 100)), 1)
    }

    func testProgressIsElapsedOverGoal() {
        XCTAssertEqual(LockedLayout.progress(elapsed: 750, goal: 1500), 0.5, accuracy: 0.0001)
        XCTAssertEqual(LockedLayout.progress(elapsed: 0, goal: 1500), 0)
    }

    func testProgressIsClampedToZeroAndOne() {
        XCTAssertEqual(LockedLayout.progress(elapsed: -5, goal: 1500), 0)
        XCTAssertEqual(LockedLayout.progress(elapsed: 2000, goal: 1500), 1)
        XCTAssertEqual(LockedLayout.progress(elapsed: 10, goal: 0), 1)
    }

    func testCountersText() {
        XCTAssertEqual(LockedLayout.countersText(blocked: 0, tabs: 0), "0 apps blocked · 0 tabs closed")
        XCTAssertEqual(LockedLayout.countersText(blocked: 3, tabs: 2), "3 apps blocked · 2 tabs closed")
        XCTAssertEqual(LockedLayout.countersText(blocked: 1, tabs: 1), "1 app blocked · 1 tab closed")
    }

    func testGoalCaption() {
        XCTAssertEqual(LockedLayout.goalCaption(goalSeconds: 25 * 60), "goal 25m")
        XCTAssertEqual(LockedLayout.goalCaption(goalSeconds: 50 * 60), "goal 50m")
        XCTAssertEqual(LockedLayout.goalCaption(goalSeconds: 90 * 60), "goal 1h 30m")
    }

    func testCenteredFrameOnALargeScreen() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)
        XCTAssertEqual(LockedLayout.centeredFrame(size: CGSize(width: 900, height: 600), in: visible),
                       CGRect(x: 270, y: 137, width: 900, height: 600))
    }

    func testCenteredFrameFollowsTheVisibleFrameOrigin() {
        let visible = CGRect(x: 100, y: 40, width: 1200, height: 800)
        XCTAssertEqual(LockedLayout.centeredFrame(size: CGSize(width: 900, height: 600), in: visible),
                       CGRect(x: 250, y: 140, width: 900, height: 600))
    }

    func testCenteredFrameShrinksToASmallScreen() {
        let visible = CGRect(x: 0, y: 25, width: 800, height: 500)
        XCTAssertEqual(LockedLayout.centeredFrame(size: CGSize(width: 900, height: 600), in: visible),
                       CGRect(x: 0, y: 25, width: 800, height: 500))
    }
}
```

- [ ] **Step 3: Run the new tests to verify they fail**

Run:

```bash
cd Tofu && xcodegen generate && xcodebuild -project Tofu.xcodeproj -scheme Tofu -destination 'platform=macOS' test -only-testing:TofuTests/MiniTimerLayoutTests -only-testing:TofuTests/LockedLayoutTests 2>&1 | tail -30
```

Expected: the test target does not compile. The errors include `error: cannot find 'MiniTimerLayout' in scope` and `error: cannot find 'LockedLayout' in scope`, followed by `** TEST FAILED **`.

- [ ] **Step 4: Create GiveUpSheet**

Create `Tofu/Tofu/UI/GiveUpSheet.swift`:

```swift
import SwiftUI

/// Friction before bailing on a goal: the user must type the give-up phrase exactly
/// (case and surrounding whitespace ignored) before Bail is enabled.
struct GiveUpSheet: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var typed = ""
    @FocusState private var isFieldFocused: Bool

    private var template: String { model.data.settings.giveUpTemplate }
    private var matches: Bool { model.engine.phraseMatches(typed, template: template) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("End early?")
                .font(.system(size: 20, weight: .semibold))
            Text("Ending early will be posted to Discord.")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text("Type this phrase to bail")
                    .font(Theme.captionFont)
                    .foregroundStyle(.secondary)
                Text(model.engine.giveUpPhrase(template: template))
                    .font(.system(size: 15, weight: .medium, design: .monospaced))
                    .padding(Theme.Space.s)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(RoundedRectangle(cornerRadius: Theme.radius)
                        .stroke(Color.primary.opacity(0.3), lineWidth: 1))
            }

            TextField("Give-up phrase", text: $typed)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13, design: .monospaced))
                .focused($isFieldFocused)
                .onSubmit { bailIfMatches() }

            HStack(spacing: Theme.Space.s) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(SecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button("Bail") { bailIfMatches() }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(!matches)
                    .opacity(matches ? 1 : 0.35)
            }
        }
        .padding(Theme.Space.l)
        .frame(width: 420)
        .onAppear { isFieldFocused = true }
    }

    /// Ends the session as a bail once the phrase matches, then closes the sheet.
    private func bailIfMatches() {
        guard matches else { return }
        let engine = model.engine
        dismiss()
        Task { await engine.bail() }
    }
}
```

- [ ] **Step 5: Replace the LockedView placeholder**

Replace the **entire** contents of `Tofu/Tofu/UI/LockedView.swift` (the Task 13 placeholder) with:

```swift
import AppKit
import SwiftUI

extension Color {
    /// Pure white in light mode and pure black in dark mode: the background of the lock-in screens.
    static let lockBackground = Color(nsColor: NSColor(name: "lockBackground") { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .black : .white
    })
}

/// Pure layout and text rules for the locked main window (unit-tested).
enum LockedLayout {
    /// Size of the main window when it is brought up from the mini timer.
    static let windowSize = CGSize(width: 900, height: 600)

    /// Giant timer font size for the space it gets: min(width / 5, height * 0.42), never below 1 pt.
    static func timerFontSize(for size: CGSize) -> CGFloat {
        let fitted = min(size.width / 5.0, size.height * 0.42)
        guard fitted.isFinite else { return 1 }
        return max(1, fitted)
    }

    /// Goal progress from 0 to 1. A goal of zero or less counts as reached.
    static func progress(elapsed: TimeInterval, goal: TimeInterval) -> Double {
        guard goal > 0 else { return 1 }
        return min(1, max(0, elapsed / goal))
    }

    /// "3 apps blocked · 2 tabs closed", singular for 1.
    static func countersText(blocked: Int, tabs: Int) -> String {
        let apps = blocked == 1 ? "app" : "apps"
        let tabWord = tabs == 1 ? "tab" : "tabs"
        return "\(blocked) \(apps) blocked · \(tabs) \(tabWord) closed"
    }

    /// "goal 50m", "goal 1h 30m".
    static func goalCaption(goalSeconds: TimeInterval) -> String {
        "goal \(TimeFormat.short(goalSeconds))"
    }

    /// `size` centered in `visible`, shrunk to fit when the screen is smaller. Origin rounded down to whole points.
    static func centeredFrame(size: CGSize, in visible: CGRect) -> CGRect {
        let width = min(size.width, visible.width)
        let height = min(size.height, visible.height)
        let x = visible.minX + ((visible.width - width) / 2).rounded(.down)
        let y = visible.minY + ((visible.height - height) / 2).rounded(.down)
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

/// Giant timer screen shown in the main window while locked: subject, timer, goal progress,
/// counters and the End button. It re-renders every tick because it reads `engine.now`
/// (through `elapsed`/`remaining`).
struct LockedView: View {
    let model: AppModel
    @State private var isConfirmingEnd = false
    @State private var isShowingGiveUp = false

    var body: some View {
        let engine = model.engine
        VStack(spacing: Theme.Space.l) {
            Text(engine.session?.subjectName ?? "")
                .font(Theme.captionFont)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            GeometryReader { proxy in
                timerBlock(engine: engine, size: proxy.size)
            }

            Text(LockedLayout.countersText(blocked: engine.session?.blockedAttempts ?? 0,
                                           tabs: engine.session?.closedTabs ?? 0))
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Button("End") { endTapped() }
                .buttonStyle(SecondaryButtonStyle())
        }
        .padding(Theme.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.lockBackground)
        .confirmationDialog("End this session?", isPresented: $isConfirmingEnd, titleVisibility: .visible) {
            Button("End session") {
                Task { await model.engine.finish() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your time so far is saved and hidden apps come back.")
        }
        .sheet(isPresented: $isShowingGiveUp) {
            GiveUpSheet(model: model)
        }
    }

    /// Timer sized to the available space, plus the goal progress line and caption in goal mode.
    private func timerBlock(engine: SessionEngine, size: CGSize) -> some View {
        VStack(spacing: Theme.Space.m) {
            Text(TimeFormat.clock(engine.remaining ?? engine.elapsed))
                .font(Theme.timerFont(size: LockedLayout.timerFontSize(for: size)))
                .lineLimit(1)
                .minimumScaleFactor(0.2)
            if let goal = engine.session?.mode.goalSeconds {
                let barWidth = size.width * 0.6
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.primary.opacity(0.15))
                    Rectangle()
                        .fill(Color.primary)
                        .frame(width: barWidth * LockedLayout.progress(elapsed: engine.elapsed, goal: goal))
                }
                .frame(width: barWidth, height: 2)
                Text(LockedLayout.goalCaption(goalSeconds: goal))
                    .font(Theme.captionFont)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    /// Goal mode before the goal needs the give-up phrase; everything else just confirms.
    private func endTapped() {
        if model.engine.needsGiveUpPhrase {
            isShowingGiveUp = true
        } else {
            isConfirmingEnd = true
        }
    }
}
```

- [ ] **Step 6: Create MiniTimerPanel**

Create `Tofu/Tofu/UI/MiniTimerPanel.swift`:

```swift
import AppKit
import SwiftUI

/// Pure geometry for the floating mini timer (unit-tested).
enum MiniTimerLayout {
    static let panelSize = CGSize(width: 240, height: 64)
    /// Gap between the top of the visible frame (below the menu bar) and the panel.
    static let topMargin: CGFloat = 8
    /// Pointer travel (points) after which a press counts as a drag instead of a click.
    static let dragThreshold: CGFloat = 3

    /// Panel frame centered horizontally at the top of `visible` (Cocoa coordinates), `topMargin` below
    /// its top edge. x is rounded down to whole points; a panel wider than `visible` is pinned to its left edge.
    static func frame(size: CGSize, visible: CGRect, topMargin: CGFloat = MiniTimerLayout.topMargin) -> CGRect {
        let x = visible.minX + max(0, ((visible.width - size.width) / 2).rounded(.down))
        let y = visible.maxY - topMargin - size.height
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    /// True once the pointer is at least `dragThreshold` points away from where the press began.
    static func isDrag(from start: CGPoint, to current: CGPoint) -> Bool {
        hypot(current.x - start.x, current.y - start.y) >= dragThreshold
    }

    /// Panel origin after the pointer moved from `mouseStart` to `mouse` (screen coordinates).
    static func draggedOrigin(_ origin: CGPoint, from mouseStart: CGPoint, to mouse: CGPoint) -> CGPoint {
        CGPoint(x: origin.x + (mouse.x - mouseStart.x), y: origin.y + (mouse.y - mouseStart.y))
    }
}

/// Rounded black/white (inverted in dark mode) pill: subject, timer and a small ✕.
/// Purely visual; clicks and drags are handled by the panel's overlay view.
struct MiniTimerView: View {
    let engine: SessionEngine

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(engine.session?.subjectName ?? "")
                    .font(Theme.captionFont)
                    .lineLimit(1)
                    .opacity(0.7)
                Text(TimeFormat.clock(engine.remaining ?? engine.elapsed))
                    .font(Theme.timerFont(size: 28))
                    .lineLimit(1)
            }
            Spacer(minLength: Theme.Space.s)
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .frame(width: 22, height: 22)
                .overlay(Circle().stroke(Color.lockBackground.opacity(0.5), lineWidth: 1))
        }
        .foregroundStyle(Color.lockBackground)
        .padding(.horizontal, Theme.Space.m)
        .frame(width: MiniTimerLayout.panelSize.width, height: MiniTimerLayout.panelSize.height)
        .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Color.primary))
    }
}

/// Transparent view on top of the SwiftUI content: a click calls `onClick`, a drag moves the window.
/// Handling the mouse here (instead of SwiftUI buttons plus isMovableByWindowBackground) keeps a drag
/// from also counting as a click, and works on the first click while the app is inactive.
@MainActor private final class ClickDragView: NSView {
    var onClick: (() -> Void)?
    private var pressMouse: CGPoint?
    private var pressOrigin: CGPoint = .zero
    private var isDragging = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        pressMouse = NSEvent.mouseLocation
        pressOrigin = window?.frame.origin ?? .zero
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = pressMouse, let window else { return }
        let mouse = NSEvent.mouseLocation
        if !isDragging {
            isDragging = MiniTimerLayout.isDrag(from: start, to: mouse)
        }
        if isDragging {
            window.setFrameOrigin(MiniTimerLayout.draggedOrigin(pressOrigin, from: start, to: mouse))
        }
    }

    override func mouseUp(with event: NSEvent) {
        let wasClick = pressMouse != nil && !isDragging
        pressMouse = nil
        isDragging = false
        if wasClick { onClick?() }
    }
}

/// Floating, non-activating mini timer shown top-center while a split/full session runs.
/// Clicking it (body or ✕) calls `onOpen`, which brings up the main window with LockedView.
@MainActor final class MiniTimerPanel: NSPanel {
    init(engine: SessionEngine, onOpen: @escaping () -> Void) {
        let size = MiniTimerLayout.panelSize
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true

        let container = NSView(frame: NSRect(origin: .zero, size: size))
        let hosting = NSHostingView(rootView: MiniTimerView(engine: engine))
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)

        let overlay = ClickDragView(frame: container.bounds)
        overlay.autoresizingMask = [.width, .height]
        overlay.onClick = onOpen
        container.addSubview(overlay)
        contentView = container
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Places the panel top-center on the main screen and shows it without activating the app.
    func show() {
        if let visible = ScreenGeometry.mainVisibleFrame() {
            setFrame(MiniTimerLayout.frame(size: MiniTimerLayout.panelSize, visible: visible), display: true)
        } else {
            center()
        }
        orderFrontRegardless()
    }
}
```

- [ ] **Step 7: Run the new tests to verify they pass**

Run:

```bash
cd Tofu && xcodegen generate && xcodebuild -project Tofu.xcodeproj -scheme Tofu -destination 'platform=macOS' test -only-testing:TofuTests/MiniTimerLayoutTests -only-testing:TofuTests/LockedLayoutTests 2>&1 | tail -30
```

Expected: `Executed 22 tests, with 0 failures (0 unexpected)` and `** TEST SUCCEEDED **`.

- [ ] **Step 8: Replace the MainWindowPresenter placeholder**

Replace the **entire** contents of `Tofu/Tofu/UI/MainWindowPresenter.swift` (the Task 13 no-op placeholder) with:

```swift
import AppKit

/// Live WindowPresenting: moves the main window into the app zone (thirds / 70-30) or swaps it for the
/// floating MiniTimerPanel (split / full), and puts everything back when the session ends.
@MainActor final class MainWindowPresenter: WindowPresenting {
    private let model: AppModel
    /// The main window as found at lock-in. Kept because an ordered-out window is invisible, and an
    /// invisible window reports `canBecomeMain == false`, so the lookup below would no longer find it.
    private weak var lockedWindow: NSWindow?
    /// Main window frame before lock-in; restored by exitLocked.
    private var savedFrame: NSRect?
    private var panel: MiniTimerPanel?

    init(model: AppModel) {
        self.model = model
    }

    /// appFrame non-nil: put main window there and show LockedView. nil: hide main window, show mini timer.
    func enterLocked(appFrame: CGRect?) {
        let window = Self.visibleMainWindow() ?? lockedWindow
        lockedWindow = window
        if savedFrame == nil {
            savedFrame = window?.frame
        }
        if let appFrame {
            closePanel()
            guard let window else { return }
            window.setFrame(appFrame, display: true, animate: true)
            bringToFront(window)
            reapplyFrameAfterSwiftUIUpdate(appFrame, to: window)
        } else {
            window?.orderOut(nil)
            showPanel()
        }
    }

    /// Mini timer click: shows the main window (900x600, centered) with LockedView in front.
    func showMainWindow() {
        guard let window = lockedWindow ?? Self.visibleMainWindow() else {
            NSApp.activate()
            return
        }
        if let visible = ScreenGeometry.mainVisibleFrame() {
            window.setFrame(LockedLayout.centeredFrame(size: LockedLayout.windowSize, in: visible), display: true)
        }
        bringToFront(window)
        window.orderFrontRegardless()
    }

    /// Close mini timer, restore main window frame, bring app to front.
    func exitLocked() {
        closePanel()
        let window = lockedWindow ?? Self.visibleMainWindow()
        let frame = savedFrame
        savedFrame = nil
        lockedWindow = nil
        guard let window else {
            NSApp.activate()
            return
        }
        if let frame {
            window.setFrame(frame, display: true, animate: window.isVisible)
        }
        bringToFront(window)
    }

    // MARK: Helpers

    /// The SwiftUI main window: a visible, non-panel, non-sheet window that can become main.
    private static func visibleMainWindow() -> NSWindow? {
        NSApp.windows.first(where: { !($0 is NSPanel) && $0.sheetParent == nil && $0.canBecomeMain })
    }

    private func bringToFront(_ window: NSWindow) {
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func showPanel() {
        closePanel()
        let panel = MiniTimerPanel(engine: model.engine) { [weak self] in
            self?.showMainWindow()
        }
        panel.show()
        self.panel = panel
    }

    private func closePanel() {
        panel?.orderOut(nil)
        panel = nil
    }

    /// RootView swaps to LockedView on SwiftUI's next update. Until then the previous content's minimum
    /// size can clamp the new frame, so apply it once more shortly after, if the session is still locked.
    private func reapplyFrameAfterSwiftUIUpdate(_ frame: CGRect, to window: NSWindow) {
        Task { @MainActor [weak self, weak window] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard let self, let window, self.model.engine.isLocked, window.frame != frame else { return }
            window.setFrame(frame, display: true)
        }
    }
}
```

- [ ] **Step 9: Build and run the full test suite**

Run:

```bash
cd Tofu && xcodegen generate && xcodebuild -project Tofu.xcodeproj -scheme Tofu -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`, with no warnings that mention `LockedView.swift`, `GiveUpSheet.swift`, `MiniTimerPanel.swift` or `MainWindowPresenter.swift`.

Run:

```bash
cd Tofu && xcodegen generate && xcodebuild -project Tofu.xcodeproj -scheme Tofu -destination 'platform=macOS' test 2>&1 | tail -30
```

Expected: `** TEST SUCCEEDED **`. Every test class from Tasks 1–13 still passes alongside `MiniTimerLayoutTests` and `LockedLayoutTests`.

- [ ] **Step 10: Commit**

```bash
cd "$(git rev-parse --show-toplevel)" && git add Tofu/Tofu/UI/LockedView.swift \
        Tofu/Tofu/UI/GiveUpSheet.swift \
        Tofu/Tofu/UI/MiniTimerPanel.swift \
        Tofu/Tofu/UI/MainWindowPresenter.swift \
        Tofu/TofuTests/MiniTimerLayoutTests.swift \
        Tofu/TofuTests/LockedLayoutTests.swift \
        Tofu/Tofu.xcodeproj
git commit -F - <<'EOF'
Add locked UI: giant timer, give-up sheet, mini timer panel, window presenter

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

Expected: `git status --short` prints nothing.

- [ ] **Step 11: Prepare the Mac and launch the built app (manual verification starts here)**

Steps 11–22 run the real lock-in on this Mac. Lock-in **hides** other apps and never quits them, but save your work in other apps first. Discord stays off for now; Settings arrives in Task 15, which checks the Discord messages.

1. Quit any running copy of Tofu.
2. Open Google Chrome so that a normal browser window of your profile is showing, not the profile picker. Leave one or two windows open with any tabs. They get minimized during each session and come back at the end.
3. Open **Notes**, **Calendar**, **Reminders** and **TextEdit** (press Cmd-N in TextEdit if it only shows an Open panel). Leave their windows visible.
4. Write down any terminal or editor you use besides Terminal and Xcode (for example iTerm2 or VS Code). You will allow it in Step 12, so it is not hidden.
5. Build into the git-ignored `build/` folder and launch the app through Launch Services, not from Xcode. That way macOS attributes the Automation prompt to Tofu itself, not to Xcode. Run from the repo root:

```bash
(cd Tofu && xcodegen generate && xcodebuild -project Tofu.xcodeproj -scheme Tofu -configuration Debug -destination 'platform=macOS' -derivedDataPath build/DerivedData build 2>&1 | tail -3) && open Tofu/build/DerivedData/Build/Products/Debug/Tofu.app
```

Expected: `** BUILD SUCCEEDED **`, then the Tofu main window opens with the sidebar ("Subjects", `+`, Stats, Settings).

- [ ] **Step 12: Create the test subject**

1. Click `+` in the sidebar. In the editor, set:
   - Name: `CS128-TEST`
   - Preset: **Left / Right**
   - Site 1: `en.wikipedia.org/wiki/Hash_table` (no scheme, on purpose)
   - Site 2: `https://docs.swift.org/swift-book/`
   - Allowed apps: **Xcode** and **Terminal**, plus the tool you wrote down in Step 11. Terminal lives in `/System/Applications/Utilities`, so search for it in the picker.
   - Extra domains: none
2. Save.

Expected:
- The picker finds Terminal.
- `CS128-TEST` appears in the sidebar.
- Its detail shows the two-box Left / Right thumbnail, both sites, and the icons of the allowed apps above the **LOCK IN** button.

Do not lock in without your terminal and editor allowed: they would be hidden too. You could still end the session from the mini timer.

- [ ] **Step 13: Lock in open-ended (Left / Right) and answer the Automation prompt**

Click **LOCK IN**, choose **Open-ended**, then confirm with **LOCK IN**.

Expected, in this order:
1. Notes, Calendar, Reminders, TextEdit and every other regular app vanish, except Chrome, Finder, Xcode, Terminal (and your allowed tool). Their Dock icons keep the running dot: they are hidden, not quit.
2. The main window disappears. The mini timer appears: a rounded 240×64 pill, horizontally centered, 8 pt below the menu bar. It is black with white text in light mode and white with black text in dark mode. It shows `CS128-TEST` in small caps, `00:00`, and a small ✕.
3. On the first lock-in of this build, macOS asks: "“Tofu” wants access to control “Google Chrome”…", followed by our usage text ("Tofu opens and arranges your study sites in Google Chrome…"). While the dialog is up, the mini timer may stay at `00:00`, because the AppleScript call waits for your answer. Click **Allow**.
4. The Chrome windows that were already open are minimized into the Dock.
5. Two new Chrome windows open. The left half shows `https://en.wikipedia.org/wiki/Hash_table`, with the scheme added automatically. The right half shows the Swift book. Together they fill the area between the menu bar and the Dock, with no gap and no overlap.
6. The mini timer counts up once per second (`00:01`, `00:02`, …) and stays above the Chrome windows while Chrome is in front.

If no prompt appears and no Chrome windows open, a stale permission decision is in the way: see Step 21.

- [ ] **Step 14: Check app blocking and toasts (Review Focus 1, ToastCenter from Task 9)**

1. Click the Notes icon in the Dock. Notes flashes for well under a second and hides again. A toast appears: `🔒 Notes is blocked during CS128-TEST`.
   - Position: top-right of the main screen, 16 pt below the menu bar and 16 pt from the right edge, 320 pt wide.
   - Colors: black with white text (inverted in dark mode).
   - It does not take focus and it disappears after about 3 s.
   - Chrome usually comes back to the front. macOS 14 may decline that activation, which is acceptable.
2. Click the Notes Dock icon three times quickly, all within 2 s. Notes is hidden every time, and at most one new toast appears.
3. Press Cmd-Tab and pick Calendar. Calendar is hidden, and the toast says `🔒 Calendar is blocked during CS128-TEST`.
4. Wait 3 s, then click the Reminders Dock icon to trigger a new toast. While it is visible, click Chrome's ⋮ menu button in the top-right corner of the right-hand Chrome window, right under the toast. The click passes through the toast and Chrome's menu opens. Press Esc.
5. Wait until no toast is showing. Then click the Dock icons of Notes, Calendar, Reminders and TextEdit as fast as you can (within 3 s).
   - At most 3 toasts are stacked, newest on top, with 8 pt gaps, and the oldest is dropped.
   - All four apps end up hidden.
6. Click Finder in the Dock, then switch to Terminal. Neither is hidden and no toast appears.

- [ ] **Step 15: Check tab blocking (Review Focus 2)**

1. Click into the left Chrome window and press Cmd-T. A blank new tab opens. Wait 5 s: it stays open, because a blank tab is never closed.
2. In that tab type `youtube.com` and press Return. Within about 2 s the tab closes and a toast says `Closed youtube.com — not part of CS128-TEST`.
3. In the left window click any article link on the Wikipedia page (same host). The page loads and its tab stays open.
4. Press Cmd-T and open `docs.swift.org/swift-book/documentation/the-swift-programming-language/thebasics/`. It loads and stays open, because the domain of site 2 is allowed in every window.

- [ ] **Step 16: Mini timer → main window, then End (open-ended)**

1. Drag the mini timer about 150 pt to the left. It follows the pointer. When you release it, the main window does **not** appear.
2. Click the mini timer once. The main window comes to the front at 900×600, centered on the screen, showing `LockedView`:
   - `CS128-TEST` in small caps at the top;
   - a giant thin monospaced timer that matches the mini timer;
   - `N apps blocked · M tabs closed`, with "app"/"tab" in the singular when the count is 1:
     - N is the number of `🔒 … is blocked` toasts that appeared during Step 14. Every counted attempt shows one, including a toast that was later pushed out of the stack. Apps hidden at lock-in itself are not counted.
     - M is `1` (the YouTube tab).
   - an outlined **End** button.

   The mini timer stays visible at the top.
3. Drag the window's edge to make it narrower and wider. The timer font shrinks and grows with the window and always stays on one line.
4. Click a Chrome window. The main window goes behind Chrome, and the mini timer stays on top. Click the ✕ on the mini timer: the main window comes back to the front.
5. Click **End**. A dialog asks "End this session?" with **End session** and **Cancel**. Click **Cancel**: the session continues and the timer keeps counting.
6. Click **End** again, then **End session**.

Expected after ending:
- The mini timer disappears. The main window returns to the exact position and size it had before Step 13, in front, with the normal (unlocked) UI.
- A toast says `Saved: <whole minutes>m on CS128-TEST`, for example `Saved: 6m on CS128-TEST`.
- Notes, Calendar, Reminders and TextEdit come back. They were hidden at lock-in.
- The Chrome windows that were minimized come back from the Dock. The two study windows stay open.
- Clicking Notes now just works (blocking is off).

An app launched for the first time *during* a session is hidden by the blocker but is not unhidden at the end: spec §6 restores only the apps hidden at lock-in. Click its Dock icon to show it.

- [ ] **Step 17: Goal mode, then bail with the give-up phrase**

1. Click **LOCK IN**, choose **25**, and confirm. The mini timer shows `25:00`, then `24:59`, `24:58`, … (counting down).
2. Click the mini timer. `LockedView` shows the countdown. Under it are a 2 pt progress line that slowly fills from the left and the caption `goal 25m`.
3. Click **End**. The "End this session?" dialog does **not** appear. Instead `GiveUpSheet` opens, showing:
   - "End early?";
   - "Ending early will be posted to Discord.";
   - the phrase `I give up on CS128-TEST` in monospace;
   - a focused text field, **Cancel**, and a dimmed **Bail**.
4. Type `I give up`. **Bail** stays dimmed and disabled, and Return does nothing.
5. Click **Cancel**. The sheet closes and the countdown continues.
6. Click **End** again. Type `  i GIVE up on cs128-test  `, with different case and extra spaces. **Bail** becomes enabled. Click it.

Expected: the sheet closes and the session ends exactly as in Step 16's "after ending" list. The toast says `Saved: 0m on CS128-TEST` or `Saved: 1m on CS128-TEST`. Task 15 checks the 🏳️ Discord message once a bot token can be entered.

- [ ] **Step 18: Goal reaching zero ends the session once (Review Focus 4)**

1. Click **LOCK IN**, choose **Custom**, enter `1` minute, and confirm. The mini timer shows `01:00` and counts down.
2. Do not touch anything. Within about 1 s of reaching `00:00`, the session ends by itself:
   - the mini timer disappears and the main window comes back;
   - the hidden apps come back;
   - **exactly one** toast appears: `Saved: 1m on CS128-TEST`.

- [ ] **Step 19: Thirds preset puts the app in its zone**

1. Select `CS128-TEST`, click **Edit**, change the preset to **Thirds** (keep both sites), and save.
2. Click **LOCK IN**, choose **Open-ended**, and confirm.

Expected:
- The main window animates into the left third of the screen, at full height between the menu bar and the Dock.
- It shows `LockedView`, with the giant timer sized to the narrow window and kept on one line.
- One second later it is still exactly in the left third; it has not snapped back to a larger size.
- The two Chrome windows fill the middle and right thirds.
- No mini timer appears.

3. Click **End**, then **End session**. The window animates back to its pre-lock position and size, and the hidden apps return.
4. Optional: set the preset to **70 / 30** with one site and lock in. Chrome fills the left 70% and our `LockedView` window the right 30%. End the session.
5. Set the preset back to **Left / Right** and save.

- [ ] **Step 20: Check dark mode**

1. Open System Settings › Appearance and choose **Dark**.
2. Lock in open-ended. The mini timer is a white pill with black text.
3. Click it. The `LockedView` background is pure black with a white timer.
4. Open Notes. The block toast is white with dark text.
5. End the session, then switch Appearance back to what it was.

- [ ] **Step 21: Automation denied, and resetting the prompt**

1. Bring the main window to the front and press Cmd-Q to quit Tofu.
2. Reset the Automation decision. Run from the repo root:

```bash
tccutil reset AppleEvents com.tofu.app
```

Expected: `Successfully reset AppleEvents approval status for com.tofu.app`.

3. Relaunch the app:

```bash
open Tofu/build/DerivedData/Build/Products/Debug/Tofu.app
```

4. Lock in open-ended. The Automation prompt from Step 13 appears again. Click **Don’t Allow**.

Expected:
- A toast says `Allow Chrome control in System Settings › Privacy & Security › Automation`.
- No Chrome window is minimized or opened.
- Other apps are still hidden, the mini timer runs, and blocked apps are still blocked.
- A `youtube.com` tab you open in Chrome is **not** closed, because the tab watch is off without permission.

5. End the session.
6. Run the `tccutil reset` command again. Lock in again, click **Allow**, and check that the Chrome windows open and tile. End the session.

Every rebuild gives the ad-hoc-signed app a new signature, so macOS may ask again after a rebuild. If Chrome control fails silently after a rebuild (the toast above appears but there was no prompt), run the `tccutil reset` command and relaunch. You can also turn it on by hand under System Settings › Privacy & Security › Automation › Tofu › Google Chrome.

- [ ] **Step 22: Cmd-Q mid-session restores the desktop (Review Focus 3)**

1. Lock in open-ended (Left / Right) and wait 5 s.
2. Click the mini timer so the main window is in front, then press Cmd-Q.

Expected:
- The app quits at once, with no dialog.
- The hidden apps reappear and the minimized Chrome windows come back.
- The mini timer is gone.

3. Check that the session was saved as interrupted. Run:

```bash
grep -c '"interrupted"' "$HOME/Library/Application Support/Tofu/store.json"
```

Expected: a number of 1 or more.

4. Relaunch with `open Tofu/build/DerivedData/Build/Products/Debug/Tofu.app`. The normal, unlocked main window opens. You can delete `CS128-TEST` from the sidebar now, or keep it for the demo rehearsal in Task 17.

- [ ] **Step 23: Fix anything that failed, then commit the fixes**

If every expectation in Steps 11–22 held, there is nothing to commit; go on to Task 15. Otherwise use this table to find the owning file, fix it, and re-run Step 9.

| Symptom | Where to look |
|---|---|
| Terminal (or another app in a subfolder) missing from the app picker | `AppCatalog` must also scan one level of subfolders such as `/System/Applications/Utilities` (Task 13) |
| Nothing changes on LOCK IN | `AppModel.lockIn` (Task 12); `AppDelegate` assigns `model.engine.presenter` (Task 13) |
| Mini timer missing, or the main window does not hide | `MainWindowPresenter.enterLocked`, `MiniTimerPanel.show` (this task) |
| Mini timer vanishes when Chrome is in front | `hidesOnDeactivate = false` in `MiniTimerPanel` (this task) |
| Clicking the mini timer does nothing, or a drag opens the window | `ClickDragView` in `MiniTimerPanel.swift` (this task) |
| Thirds window snaps back to a larger size | `RootView` must not put a minimum frame on the locked branch (Task 13); `reapplyFrameAfterSwiftUIUpdate` (this task) |
| Main window not restored after End | `MainWindowPresenter.exitLocked` (this task); `SessionEngine.finalize` calls `presenter?.exitLocked()` (Task 10) |
| Other apps not hidden, or not unhidden at the end | `WorkspaceController` (Task 7) |
| Blocked app stays visible, or attempts are over-counted | `AppBlocker`, `AttemptDebouncer` (Task 7) |
| Chrome windows not opened or in the wrong place | `ChromeController.prepare`, `ChromeScripts.openWindow` (Task 8); `ScreenGeometry.chromeBounds` (Task 3) |
| Off-topic tab not closed, or a blank tab closed | `ChromeController.startTabWatch` (Task 8); `DomainMatcher.isAllowed` (Task 4) |
| No toast, or toasts in the wrong place | `ToastCenter`, `ToastLayout` (Task 9) |
| Timer frozen while not waiting on a system dialog | `SessionEngine` 1 s timer (Task 10) |
| Give-up phrase never matches | `SessionEngine.phraseMatches` (Task 10); `model.data.settings.giveUpTemplate` (Task 2 default `I give up on {subject}`) |

After a fix passes Step 9 and the failing manual step, commit:

```bash
cd "$(git rev-parse --show-toplevel)" && git add Tofu/Tofu Tofu/TofuTests Tofu/Tofu.xcodeproj
git commit -F - <<'EOF'
Fix issues found in end-to-end lock-in verification

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

Expected: `git status --short` prints nothing.

### Task 15: SettingsView

This task replaces the Task 13 placeholder `UI/SettingsView.swift` with the real Settings screen from spec §11. It is a grouped `Form` with six sections:

| Section | Contents |
|---|---|
| Profile | The display name used in Discord messages. |
| Discord | The "post" toggle, a bot token field with Save and Remove, and Test connection. |
| Discord setup | Numbered bot setup steps, the Application ID field, and the invite link. |
| Accountability | The give-up phrase template, with a live preview for "CS128". |
| Chrome | Automation status and a Request access button. |
| Demo | Load and clear demo data, with a count of demo sessions. |

Every status string comes from the pure `SettingsStatus` enum (`Engine/SettingsStatus.swift`), so the texts are unit-tested. The same goes for the invite-URL builder, the phrase preview and the token clean-up. The view itself is a thin layer over `AppModel`.

**Why each piece works the way it does:**

- **Settings changes go through `model.updateSettings`.** `AppModel` saves after every mutation, so nothing extra is persisted here.
- **"Token saved in Keychain" is driven by a local `@State hasToken`.** It is refreshed on appear, after Save and after Remove. `AppModel.discordToken` reads the Keychain and is not necessarily observable, so the view can't rely on it to update.
- **The bot token never leaves the Keychain.** The `SecureField` is cleared after Save.
- **The Application ID is not a secret.** It only builds the invite link, so it lives in `@AppStorage("discordAppID")`.
- **Request access runs `ChromeController().requestAccess()`.** That call is synchronous and blocks until macOS's Automation prompt is answered. So the button first shows "Waiting for macOS…", then yields for 150 ms so the text can render, then runs the call.

**Files:**
- Create: `Tofu/Tofu/Engine/SettingsStatus.swift`
- Modify (replace the Task 13 placeholder entirely): `Tofu/Tofu/UI/SettingsView.swift`
- Test: `Tofu/TofuTests/SettingsStatusTests.swift`
- Modify (regenerated by `xcodegen generate`): `Tofu/Tofu.xcodeproj`

**Interfaces:**
- Consumes:
  - Task 2: `struct AppSettings { var displayName: String; var discordEnabled: Bool; var giveUpTemplate: String; var channelCache: [String: String] }` and `struct Session { var isDemo: Bool }`
  - Task 6:
    - `final class DiscordClient` with `init(token: String, transport: HTTPTransport = URLSessionTransport(), sleep: @escaping (TimeInterval) async -> Void = { seconds in try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000)) })`, `func me() async throws -> DiscordUser` and `func guilds() async throws -> [DiscordGuild]`
    - `struct DiscordUser: Decodable, Equatable { let id: String; let username: String }`
    - `enum DiscordError: Error, Equatable { case http(Int); case transport(String); case decoding }`
  - Task 8:
    - `enum ChromeError: Error, Equatable { case notInstalled, automationDenied, profileNotReady, scriptFailed(String) }`
    - `@MainActor final class ChromeController` with `static var isInstalled: Bool`, `init()` and `func requestAccess() -> ChromeError?`
  - Task 12: `@Observable @MainActor final class AppModel` with:
    - `var data: StoreData`
    - `func updateSettings(_ mutate: (inout AppSettings) -> Void)`
    - `var discordToken: String? { get }`
    - `func setDiscordToken(_ token: String?)`
    - `func loadDemoData()`
    - `func clearDemoData()`
  - Task 13: `enum Theme { enum Space { static let xs: CGFloat; static let s: CGFloat } }` (`UI/Theme.swift`). The `SettingsView(model:)` call sites are the sidebar detail and the Settings scene.
- Produces:
  - `struct SettingsView: View { let model: AppModel }`, created as `SettingsView(model:)`. This is unchanged from the Task 13 placeholder. The `@State`/`@AppStorage` properties are private and have initial values, so the memberwise init keeps only `model`.
  - Additive. Nothing outside this task depends on it:

    ```swift
    enum SettingsStatus {
        static let noToken: String            // "Save a bot token first"
        static let testing: String            // "Testing…"
        static let chromeUnchecked: String    // "Not checked yet"
        static let chromeWaiting: String      // "Waiting for macOS…"
        static let inviteTemplate: String     // "https://discord.com/oauth2/authorize?client_id=<APP_ID>&scope=bot&permissions=3072"
        static func discordResult(_ result: Result<(user: DiscordUser, guildCount: Int), Error>) -> String
        static func chromeResult(_ error: ChromeError?) -> String
        static func inviteURL(appID: String) -> URL?
        static func phrasePreview(template: String, subject: String = "CS128") -> String
        static func demoSummary(count: Int) -> String
        static func cleanedToken(_ raw: String) -> String?
    }
    ```

- [ ] **Step 1: Write the failing SettingsStatus tests**

The tests cover:

- `discordResult` for success (0, 1 and 3 servers), `http(401)`, any other HTTP code, `transport`, `decoding`, and a non-Discord error;
- `chromeResult` for `nil` and each `ChromeError`;
- the invite URL builder:
  - `nil` for empty, blank, non-numeric, negative, spaced and full-width ids;
  - the exact spec §9 URL for `"123"`, and for a padded 19-digit id;
- the phrase preview, the demo count text and token clean-up.

Create `Tofu/TofuTests/SettingsStatusTests.swift`:

```swift
import XCTest
@testable import Tofu

final class SettingsStatusTests: XCTestCase {
    private let bot = DiscordUser(id: "42", username: "lockbot")

    // MARK: - Discord test connection

    func testDiscordSuccessShowsUsernameAndServerCount() {
        XCTAssertEqual(SettingsStatus.discordResult(.success((user: bot, guildCount: 3))),
                       "Connected as lockbot · 3 servers")
    }

    func testDiscordSuccessWithOneServerIsSingular() {
        XCTAssertEqual(SettingsStatus.discordResult(.success((user: bot, guildCount: 1))),
                       "Connected as lockbot · 1 server")
    }

    func testDiscordSuccessWithNoServersAsksForAnInvite() {
        XCTAssertEqual(SettingsStatus.discordResult(.success((user: bot, guildCount: 0))),
                       "Connected as lockbot · 0 servers — invite the bot to a server")
    }

    func testDiscordHTTP401PointsAtTheToken() {
        XCTAssertEqual(SettingsStatus.discordResult(.failure(DiscordError.http(401))),
                       "Failed: HTTP 401 — the bot token is invalid")
    }

    func testDiscordOtherHTTPStatusShowsTheCode() {
        XCTAssertEqual(SettingsStatus.discordResult(.failure(DiscordError.http(403))), "Failed: HTTP 403")
        XCTAssertEqual(SettingsStatus.discordResult(.failure(DiscordError.http(500))), "Failed: HTTP 500")
    }

    func testDiscordTransportErrorShowsTheMessage() {
        let error = DiscordError.transport("The Internet connection appears to be offline.")
        XCTAssertEqual(SettingsStatus.discordResult(.failure(error)),
                       "Failed: network error (The Internet connection appears to be offline.)")
    }

    func testDiscordDecodingError() {
        XCTAssertEqual(SettingsStatus.discordResult(.failure(DiscordError.decoding)),
                       "Failed: unexpected response from Discord")
    }

    func testNonDiscordErrorUsesItsLocalizedDescription() {
        let error = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "boom"])
        XCTAssertEqual(SettingsStatus.discordResult(.failure(error)), "Failed: boom")
    }

    // MARK: - Chrome request access

    func testChromeAllowedWhenThereIsNoError() {
        XCTAssertEqual(SettingsStatus.chromeResult(nil), "Chrome control allowed")
    }

    func testChromeResultForEachError() {
        XCTAssertEqual(SettingsStatus.chromeResult(.notInstalled), "Google Chrome not installed")
        XCTAssertEqual(SettingsStatus.chromeResult(.automationDenied),
                       "Denied — enable in System Settings › Privacy & Security › Automation")
        XCTAssertEqual(SettingsStatus.chromeResult(.profileNotReady),
                       "Chrome is still starting — try again in a moment")
        XCTAssertEqual(SettingsStatus.chromeResult(.scriptFailed("Syntax error")),
                       "Chrome script failed: Syntax error")
    }

    // MARK: - Invite URL

    func testInviteURLForNumericApplicationID() {
        XCTAssertEqual(SettingsStatus.inviteURL(appID: "123")?.absoluteString,
                       "https://discord.com/oauth2/authorize?client_id=123&scope=bot&permissions=3072")
        XCTAssertEqual(SettingsStatus.inviteURL(appID: "  1234567890123456789\n")?.absoluteString,
                       "https://discord.com/oauth2/authorize?client_id=1234567890123456789&scope=bot&permissions=3072")
    }

    func testInviteURLIsNilForEmptyOrNonNumericID() {
        XCTAssertNil(SettingsStatus.inviteURL(appID: ""))
        XCTAssertNil(SettingsStatus.inviteURL(appID: "   "))
        XCTAssertNil(SettingsStatus.inviteURL(appID: "abc"))
        XCTAssertNil(SettingsStatus.inviteURL(appID: "12a3"))
        XCTAssertNil(SettingsStatus.inviteURL(appID: "-123"))
        XCTAssertNil(SettingsStatus.inviteURL(appID: "1 23"))
        XCTAssertNil(SettingsStatus.inviteURL(appID: "１２３"))   // full-width digits
    }

    func testInviteTemplateMatchesTheSpec() {
        XCTAssertEqual(SettingsStatus.inviteTemplate,
                       "https://discord.com/oauth2/authorize?client_id=<APP_ID>&scope=bot&permissions=3072")
    }

    // MARK: - Small texts

    func testPhrasePreviewReplacesEverySubjectPlaceholder() {
        XCTAssertEqual(SettingsStatus.phrasePreview(template: "I give up on {subject}"), "I give up on CS128")
        XCTAssertEqual(SettingsStatus.phrasePreview(template: "{subject} beat me, bye {subject}", subject: "MATH241"),
                       "MATH241 beat me, bye MATH241")
        XCTAssertEqual(SettingsStatus.phrasePreview(template: "I quit"), "I quit")
    }

    func testDemoSummary() {
        XCTAssertEqual(SettingsStatus.demoSummary(count: 0), "No demo data loaded")
        XCTAssertEqual(SettingsStatus.demoSummary(count: 1), "1 demo session loaded")
        XCTAssertEqual(SettingsStatus.demoSummary(count: 43), "43 demo sessions loaded")
    }

    func testCleanedTokenTrimsWhitespaceAndBotPrefix() {
        XCTAssertEqual(SettingsStatus.cleanedToken("  abc.def.ghi \n"), "abc.def.ghi")
        XCTAssertEqual(SettingsStatus.cleanedToken("Bot abc.def.ghi"), "abc.def.ghi")
        XCTAssertEqual(SettingsStatus.cleanedToken(" Bot   abc.def.ghi "), "abc.def.ghi")
        XCTAssertNil(SettingsStatus.cleanedToken(""))
        XCTAssertNil(SettingsStatus.cleanedToken("  \n "))
    }
}
```

- [ ] **Step 2: Run the SettingsStatus tests and watch them fail**

Run from the repo root:

```bash
cd Tofu && xcodegen generate && xcodebuild -project Tofu.xcodeproj -scheme Tofu -destination 'platform=macOS' test -only-testing:TofuTests/SettingsStatusTests 2>&1 | tail -30
```

Expected: the test target does not compile. The output contains `error: cannot find 'SettingsStatus' in scope` and ends with `** TEST FAILED **`.

- [ ] **Step 3: Implement SettingsStatus**

Create `Tofu/Tofu/Engine/SettingsStatus.swift`:

```swift
import Foundation

/// Pure texts and helpers for the Settings screen (status lines, invite link, previews).
enum SettingsStatus {
    /// Shown by "Test connection" when no bot token is saved.
    static let noToken = "Save a bot token first"
    /// Shown while "Test connection" runs.
    static let testing = "Testing…"
    /// Shown in the Chrome section before "Request access" has been clicked.
    static let chromeUnchecked = "Not checked yet"
    /// Shown while the Automation request (and possibly the macOS prompt) is pending.
    static let chromeWaiting = "Waiting for macOS…"
    /// Spec §9 invite link; `<APP_ID>` is the Discord application id. 3072 = View Channel + Send Messages.
    static let inviteTemplate = "https://discord.com/oauth2/authorize?client_id=<APP_ID>&scope=bot&permissions=3072"

    /// Status line for Settings › Discord › Test connection.
    /// Success: "Connected as lockbot · 3 servers". Failure: "Failed: HTTP 401 — the bot token is invalid".
    static func discordResult(_ result: Result<(user: DiscordUser, guildCount: Int), Error>) -> String {
        switch result {
        case .success(let value):
            let servers = value.guildCount == 1 ? "1 server" : "\(value.guildCount) servers"
            let text = "Connected as \(value.user.username) · \(servers)"
            return value.guildCount == 0 ? text + " — invite the bot to a server" : text
        case .failure(let error):
            return "Failed: " + describe(error)
        }
    }

    /// Status line for Settings › Chrome › Request access. nil means the script ran, so control is allowed.
    static func chromeResult(_ error: ChromeError?) -> String {
        guard let error else { return "Chrome control allowed" }
        switch error {
        case .notInstalled:
            return "Google Chrome not installed"
        case .automationDenied:
            return "Denied — enable in System Settings › Privacy & Security › Automation"
        case .profileNotReady:
            return "Chrome is still starting — try again in a moment"
        case .scriptFailed(let message):
            return "Chrome script failed: \(message)"
        }
    }

    /// The bot invite URL for a Discord application id, or nil unless the trimmed id is non-empty ASCII digits.
    static func inviteURL(appID: String) -> URL? {
        let id = appID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, id.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return URL(string: inviteTemplate.replacingOccurrences(of: "<APP_ID>", with: id))
    }

    /// The give-up phrase as it will appear for `subject` (same substitution as SessionEngine.giveUpPhrase).
    static func phrasePreview(template: String, subject: String = "CS128") -> String {
        template.replacingOccurrences(of: "{subject}", with: subject)
    }

    /// "No demo data loaded", "1 demo session loaded", "43 demo sessions loaded".
    static func demoSummary(count: Int) -> String {
        switch count {
        case ...0: return "No demo data loaded"
        case 1: return "1 demo session loaded"
        default: return "\(count) demo sessions loaded"
        }
    }

    /// Token as typed/pasted: trims whitespace and a leading "Bot " prefix. nil when nothing is left.
    static func cleanedToken(_ raw: String) -> String? {
        var token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if token.hasPrefix("Bot ") {
            token = String(token.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return token.isEmpty ? nil : token
    }

    private static func describe(_ error: Error) -> String {
        guard let discordError = error as? DiscordError else { return error.localizedDescription }
        switch discordError {
        case .http(401):
            return "HTTP 401 — the bot token is invalid"
        case .http(let code):
            return "HTTP \(code)"
        case .transport(let message):
            return "network error (\(message))"
        case .decoding:
            return "unexpected response from Discord"
        }
    }
}
```

- [ ] **Step 4: Run the SettingsStatus tests and watch them pass**

Run from the repo root:

```bash
cd Tofu && xcodegen generate && xcodebuild -project Tofu.xcodeproj -scheme Tofu -destination 'platform=macOS' test -only-testing:TofuTests/SettingsStatusTests 2>&1 | tail -30
```

Expected: `Test Suite 'SettingsStatusTests' passed`, `Executed 16 tests, with 0 failures (0 unexpected)` and `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit SettingsStatus**

```bash
cd "$(git rev-parse --show-toplevel)" && git add Tofu/Tofu/Engine/SettingsStatus.swift Tofu/TofuTests/SettingsStatusTests.swift Tofu/Tofu.xcodeproj && git commit -F - <<'EOF'
Add SettingsStatus: Discord/Chrome status texts and invite URL builder

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

- [ ] **Step 6: Replace the SettingsView placeholder**

Replace the whole content of `Tofu/Tofu/UI/SettingsView.swift` with:

```swift
import SwiftUI

/// Settings (spec §11): profile, Discord bot, give-up phrase, Chrome automation, demo data.
/// Used both as the sidebar's Settings detail and in the app's Settings scene.
struct SettingsView: View {
    let model: AppModel

    /// Discord application id, only used to build the invite link. Not a secret, so UserDefaults is fine.
    @AppStorage("discordAppID") private var discordAppID = ""
    @State private var tokenDraft = ""
    @State private var hasToken = false
    @State private var discordStatus = ""
    @State private var isTesting = false
    @State private var chromeStatus = SettingsStatus.chromeUnchecked
    @State private var isRequestingChrome = false

    var body: some View {
        Form {
            profileSection
            discordSection
            discordSetupSection
            accountabilitySection
            chromeSection
            demoSection
        }
        .formStyle(.grouped)
        .frame(minWidth: 480, idealWidth: 560, minHeight: 480, idealHeight: 720)
        .navigationTitle("Settings")
        .onAppear(perform: refresh)
    }

    // MARK: - Sections

    private var profileSection: some View {
        Section {
            TextField("Display name", text: displayName)
        } header: {
            Text("Profile")
        } footer: {
            Text("Shown in Discord messages, e.g. “\(model.data.settings.displayName) is locked in on CS128”.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var discordSection: some View {
        Section {
            Toggle("Post lock-ins to Discord", isOn: discordEnabled)
            HStack {
                SecureField("Bot token", text: $tokenDraft)
                    .onSubmit(saveToken)
                Button("Save", action: saveToken)
                    .disabled(SettingsStatus.cleanedToken(tokenDraft) == nil)
            }
            if hasToken {
                HStack {
                    Label("Token saved in Keychain", systemImage: "lock.fill")
                    Spacer()
                    Button("Remove", action: removeToken)
                }
            }
            HStack(spacing: Theme.Space.s) {
                Button("Test connection", action: testConnection)
                    .disabled(!hasToken || isTesting)
                if isTesting {
                    ProgressView().controlSize(.small)
                }
                Text(discordStatus)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        } header: {
            Text("Discord")
        } footer: {
            Text("The bot posts when you lock in, finish, or bail. Bots can't join group DMs, so it posts in one text channel per server it is in.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var discordSetupSection: some View {
        Section("Discord setup") {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("1. Create an application at [discord.com/developers/applications](https://discord.com/developers/applications).")
                Text("2. Open **Bot**, click **Reset Token**, copy the token and paste it above, then click Save.")
                Text("3. Copy the **Application ID** from General Information into the field below and open the invite link.")
                Text("4. In your server, create a text channel named **#lock-in** (#locked-in, #lockin and #accountability also work).")
            }
            .fixedSize(horizontal: false, vertical: true)
            TextField("Application ID", text: $discordAppID)
            if let url = SettingsStatus.inviteURL(appID: discordAppID) {
                Link("Invite the bot to a server", destination: url)
            } else {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    if !discordAppID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("The Application ID is a number, e.g. 1234567890123456789.")
                    }
                    Text(SettingsStatus.inviteTemplate)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
                .foregroundStyle(.secondary)
            }
        }
    }

    private var accountabilitySection: some View {
        Section {
            TextField("Give-up phrase", text: giveUpTemplate)
            LabeledContent("Preview") {
                Text("“\(SettingsStatus.phrasePreview(template: model.data.settings.giveUpTemplate))”")
            }
        } header: {
            Text("Accountability")
        } footer: {
            Text("Ending a goal session early means typing this phrase. {subject} becomes the subject name.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var chromeSection: some View {
        Section {
            LabeledContent("Automation") {
                Text(chromeStatus)
                    .multilineTextAlignment(.trailing)
            }
            Button("Request access", action: requestChromeAccess)
                .disabled(isRequestingChrome)
        } header: {
            Text("Chrome")
        } footer: {
            Text("macOS asks once: “Tofu wants to control Google Chrome.” Allow it so study sites open and off-topic tabs close. No Accessibility permission is needed.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var demoSection: some View {
        let demoCount = model.data.sessions.filter(\.isDemo).count
        return Section {
            Text(SettingsStatus.demoSummary(count: demoCount))
            HStack {
                Button("Load demo data") { model.loadDemoData() }
                    .disabled(demoCount > 0)
                Button("Clear demo data") { model.clearDemoData() }
                    .disabled(demoCount == 0)
            }
        } header: {
            Text("Demo")
        } footer: {
            Text("Load adds about 30 days of sample sessions (and CS128 and MATH241 if you have no subjects) so Stats looks full. Clear removes the sample sessions again.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Bindings

    private var displayName: Binding<String> {
        Binding(get: { model.data.settings.displayName },
                set: { newValue in model.updateSettings { $0.displayName = newValue } })
    }

    private var discordEnabled: Binding<Bool> {
        Binding(get: { model.data.settings.discordEnabled },
                set: { newValue in model.updateSettings { $0.discordEnabled = newValue } })
    }

    private var giveUpTemplate: Binding<String> {
        Binding(get: { model.data.settings.giveUpTemplate },
                set: { newValue in model.updateSettings { $0.giveUpTemplate = newValue } })
    }

    // MARK: - Actions

    private func refresh() {
        hasToken = model.discordToken != nil
        if !ChromeController.isInstalled {
            chromeStatus = SettingsStatus.chromeResult(.notInstalled)
        }
    }

    private func saveToken() {
        guard let token = SettingsStatus.cleanedToken(tokenDraft) else { return }
        model.setDiscordToken(token)
        tokenDraft = ""
        hasToken = model.discordToken != nil
        discordStatus = ""
    }

    private func removeToken() {
        model.setDiscordToken(nil)
        hasToken = model.discordToken != nil
        discordStatus = ""
    }

    /// GET /users/@me then /users/@me/guilds with the saved token; shows the result text.
    private func testConnection() {
        guard let token = model.discordToken else {
            discordStatus = SettingsStatus.noToken
            return
        }
        isTesting = true
        discordStatus = SettingsStatus.testing
        Task { @MainActor in
            let client = DiscordClient(token: token)
            let result: Result<(user: DiscordUser, guildCount: Int), Error>
            do {
                let user = try await client.me()
                let guilds = try await client.guilds()
                result = .success((user: user, guildCount: guilds.count))
            } catch {
                result = .failure(error)
            }
            discordStatus = SettingsStatus.discordResult(result)
            isTesting = false
        }
    }

    /// Runs the harmless ping script, which makes macOS show the Automation prompt the first time.
    private func requestChromeAccess() {
        isRequestingChrome = true
        chromeStatus = SettingsStatus.chromeWaiting
        Task { @MainActor in
            // Let the waiting text render first: the Apple Event blocks until the prompt is answered.
            try? await Task.sleep(nanoseconds: 150_000_000)
            chromeStatus = SettingsStatus.chromeResult(ChromeController().requestAccess())
            isRequestingChrome = false
        }
    }
}
```

- [ ] **Step 7: Build the app**

Run from the repo root:

```bash
(cd Tofu && xcodegen generate && xcodebuild -project Tofu.xcodeproj -scheme Tofu -configuration Debug -destination 'platform=macOS' -derivedDataPath build/DerivedData build 2>&1 | tail -5)
```

Expected: `** BUILD SUCCEEDED **` with no errors. `build/` is already in `.gitignore`.

If the build fails with `'SettingsView' initializer is inaccessible due to 'private' protection level`, a private stored property lost its initial value. Every `@State`/`@AppStorage` property in this file must keep its `= …` default.

- [ ] **Step 8: Verify Settings by hand**

Launch the build from the repo root. Nothing in this step locks in, so no apps get hidden.

```bash
open Tofu/build/DerivedData/Build/Products/Debug/Tofu.app
```

Click **Settings** in the sidebar and check each item:

1. **Layout.**
   - The window shows a grouped form with these sections, in order: **Profile**, **Discord**, **Discord setup**, **Accountability**, **Chrome**, **Demo**.
   - Everything is black, white and gray, including the toggle, links and buttons.
   - Repeat in dark mode (System Settings › Appearance › Dark). The form turns white on black, still with no color.
2. **Display name.**
   1. Change it to `Alex Test`. The Profile footer reads `Shown in Discord messages, e.g. “Alex Test is locked in on CS128”.`
   2. Quit with ⌘Q and relaunch. The field still shows `Alex Test`.
   3. Run:

      ```bash
      grep '"displayName"' ~/Library/Application\ Support/Tofu/store.json
      ```

      Expected: `"displayName" : "Alex Test",`.
3. **Give-up phrase.**
   - Type `I'm done with {subject}`. **Preview** shows `“I'm done with CS128”`.
   - Put it back to `I give up on {subject}`.
4. **Application ID.**
   - With the field empty, the literal template `https://discord.com/oauth2/authorize?client_id=<APP_ID>&scope=bot&permissions=3072` shows in gray.
   - Type `abc`. The hint `The Application ID is a number, e.g. 1234567890123456789.` appears.
   - Replace the text with `123`. The hint and template are replaced by a clickable link, **Invite the bot to a server**. Don't click it: application 123 does not exist.
   - Clear the field again.
5. **Bot token.**
   1. Paste `Bot fake.token.value` into **Bot token** and click **Save**:
      - the field clears;
      - a row with a lock icon and **Token saved in Keychain** appears, with a **Remove** button;
      - **Test connection** becomes enabled.
   2. Run:

      ```bash
      grep -c "fake.token" ~/Library/Application\ Support/Tofu/store.json
      ```

      Expected: `0`, because the token is only in the Keychain.
   3. Quit and relaunch. **Token saved in Keychain** is still shown.
6. **Test connection (bad token).**
   1. Click **Test connection**. A small spinner and `Testing…` appear.
   2. Within a few seconds, the text becomes `Failed: HTTP 401 — the bot token is invalid`.
   3. With Wi-Fi turned off, it shows `Failed: network error (The Internet connection appears to be offline.)` instead.
7. **Remove.**
   - Click **Remove**. The Keychain row disappears and **Test connection** is disabled.
   - If you have a real bot token, save it now. **Test connection** then shows `Connected as <bot name> · <n> servers` (`1 server` for exactly one).
8. **Discord toggle.**
   - Turn on **Post lock-ins to Discord**. Quit and relaunch: it is still on.
   - `grep '"discordEnabled"' ~/Library/Application\ Support/Tofu/store.json` prints `"discordEnabled" : true,`.
9. **Chrome.**
   1. Before any click, **Automation** reads:
      - `Not checked yet`;
      - or `Google Chrome not installed` on a Mac without Chrome.
   2. Click **Request access**:
      - The text changes to `Waiting for macOS…`.
      - Chrome launches if it isn't running.
      - The first time, macOS shows "“Tofu” wants access to control “Google Chrome”…".
   3. Allow it. The status becomes `Chrome control allowed`.
   4. If you deny instead, it shows `Denied — enable in System Settings › Privacy & Security › Automation`.

   To see the prompt again later, run `tccutil reset AppleEvents com.tofu.app` and relaunch the app.
10. **Demo.**
    1. The section shows `No demo data loaded`. **Load demo data** is enabled and **Clear demo data** is disabled.
    2. Click **Load demo data**. The text becomes `N demo sessions loaded`, where N is about 40. **Load** becomes disabled and **Clear** enabled.
    3. Click **Clear demo data**. The section is back to `No demo data loaded`.

Quit the app when done.

- [ ] **Step 9: Run the full test suite**

Run from the repo root:

```bash
cd Tofu && xcodegen generate && xcodebuild -project Tofu.xcodeproj -scheme Tofu -destination 'platform=macOS' test 2>&1 | tail -30
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 10: Commit SettingsView**

```bash
cd "$(git rev-parse --show-toplevel)" && git add Tofu/Tofu/UI/SettingsView.swift Tofu/Tofu.xcodeproj && git commit -F - <<'EOF'
Build Settings: profile, Discord token/test/invite, give-up phrase, Chrome access, demo data

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

Expected: `git status --short` prints nothing.

---

### Task 16: StatsView + SubjectStatsSection

This task replaces the Task 13 placeholder `UI/StatsView.swift` with the real stats screens from spec §10–11.

**`StatsView(model:)`** shows:

1. a **Day / Week / Month** segmented picker over `StatsRange`;
2. a Swift Charts stacked `BarMark` chart:
   - one bar per bucket;
   - minutes on a y-axis titled "min";
   - one gray per subject, from `Theme.gray(at:)`, with "Other" last and lightest;
3. the ten summary `StatCard`s;
4. a per-subject breakdown: a proportional `Color.primary` bar, `TimeFormat.short` total and a rounded percent for each subject.

**`SubjectStatsSection(model:subjectID:)`** filters the sessions to one subject. It shows four cards (Total, Sessions, Average, Streak) and a 14-day mini bar chart.

When no session has ended yet, both show `No sessions yet — lock in to start tracking.`

The decisions that need logic live in the pure `StatsFormatting` enum (`Engine/StatsFormatting.swift`), which is unit-tested:

| Helper | What it decides |
|---|---|
| `chartSubjects` | Series order: total minutes descending, ties by name, "Other" last. Series without minutes are dropped. |
| `topSubjectLimit` | Every subject gets its own gray while they fit in the 5 shades; otherwise the top 4 plus "Other". This means "Other" never reuses the first shade. |
| `axisLabels` / `maxAxisLabels` | 7 of 14 day labels, 6 of 12 week labels, all 12 month labels. The newest label is always shown, so labels don't truncate to "Se…" in a narrow window. |
| `streak` | "1 day" / "N days" |
| `percent` | Rounded whole percent |
| `clampedFraction` | Bar width, clamped to 0…1 |
| `totalSeconds` | Total of ended sessions only |
| `hasTrackedSessions` | Whether any session has ended (picks the empty state) |
| `rangeCaption`, `emptyMessage` | Fixed texts |

**Refreshing.** Both views build `StatsEngine(now: max(model.engine.now, Date()))`:

- Reading `model.engine.now` (an observed property) refreshes the views on every engine tick.
- `Date()` keeps "today" correct while the app is idle and `now` is not ticking.

**The x axis is categorical.** It uses the bucket labels, with an explicit domain `chartXScale(domain: buckets.map(\.label))`. As a result:

- every bucket keeps its slot, even when it has no minutes;
- the slots stay in chronological order.

`StatsEngine` guarantees the labels are unique inside each range: 14 consecutive days, 12 consecutive weeks, or 12 consecutive months.

**Files:**
- Create: `Tofu/Tofu/Engine/StatsFormatting.swift`
- Modify (replace the Task 13 placeholder entirely): `Tofu/Tofu/UI/StatsView.swift`
- Test: `Tofu/TofuTests/StatsFormattingTests.swift`
- Modify (regenerated by `xcodegen generate`): `Tofu/Tofu.xcodeproj`

**Interfaces:**
- Consumes:
  - Task 2: `struct Session` with `subjectID: UUID`, `subjectName: String`, `end: Date?`, `var duration: TimeInterval`, and `init(id: UUID = UUID(), subjectID: UUID, subjectName: String, mode: SessionMode, start: Date, end: Date? = nil, lastHeartbeat: Date? = nil, blockedAttempts: Int = 0, closedTabs: Int = 0, outcome: SessionOutcome? = nil, isDemo: Bool = false)`. Also `struct StoreData { var sessions: [Session] }`.
  - Task 5: `static func TimeFormat.short(_ seconds: TimeInterval) -> String`
  - Task 11:
    - `enum StatsRange: String, CaseIterable, Identifiable { case day, week, month; var title: String }`
    - `struct StatsBucket: Identifiable, Equatable { let start: Date; let label: String; let minutesBySubject: [String: Double]; var id: Date; var totalMinutes: Double }`
    - `struct StatsSummary` (all ten fields)
    - `struct SubjectShare: Identifiable, Equatable { let name: String; let seconds: TimeInterval; let fraction: Double }`
    - `struct StatsEngine` with `static let otherLabel = "Other"`, `init(calendar: Calendar = .current, now: Date = Date())`, `func buckets(_ sessions: [Session], range: StatsRange, topSubjects: Int = 5) -> [StatsBucket]`, `func summary(_ sessions: [Session]) -> StatsSummary` and `func shares(_ sessions: [Session]) -> [SubjectShare]`
  - Task 12: `AppModel.data: StoreData` and `AppModel.engine: SessionEngine` (`private(set) var now: Date`)
  - Task 13 (`UI/Theme.swift`):
    - `Theme.grays: [Color]` (5 shades)
    - `static func Theme.gray(at index: Int) -> Color`
    - `Theme.Space.s` / `.m` / `.l`
    - `Theme.titleFont`, `Theme.captionFont`
    - `struct StatCard: View { let title: String; let value: String }`
- Produces:
  - `struct StatsView: View { let model: AppModel }`, created as `StatsView(model:)` (unchanged from the Task 13 placeholder)
  - `struct SubjectStatsSection: View { let model: AppModel; let subjectID: UUID }`, created as `SubjectStatsSection(model:subjectID:)` (unchanged from the Task 13 placeholder)
  - Additive. Nothing outside this task depends on it:

    ```swift
    enum StatsFormatting {
        static let emptyMessage: String   // "No sessions yet — lock in to start tracking."
        static func rangeCaption(_ range: StatsRange) -> String
        static func streak(_ days: Int) -> String
        static func clampedFraction(_ fraction: Double) -> Double
        static func percent(_ fraction: Double) -> String
        static func chartSubjects(_ buckets: [StatsBucket]) -> [String]
        static func maxAxisLabels(_ range: StatsRange) -> Int
        static func axisLabels(_ labels: [String], maxCount: Int) -> [String]
        static func topSubjectLimit(for sessions: [Session], shades: Int) -> Int
        static func hasTrackedSessions(_ sessions: [Session]) -> Bool
        static func totalSeconds(_ sessions: [Session]) -> TimeInterval
    }
    ```

  - File-private helpers inside `StatsView.swift`: `StatsStackedChart`, `StatsDayChart`, `StatsSummaryGrid`, `StatsSubjectBreakdown`, `StatsShareBar`, `bucketAxis(_:maxLabels:)` and `statsGridColumns`.

- [ ] **Step 1: Write the failing StatsFormatting tests**

Create `Tofu/TofuTests/StatsFormattingTests.swift`:

```swift
import XCTest
@testable import Tofu

final class StatsFormattingTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_760_000_000)

    private func bucket(_ dayOffset: Int, _ minutes: [String: Double]) -> StatsBucket {
        let day = start.addingTimeInterval(TimeInterval(dayOffset) * 86_400)
        return StatsBucket(start: day, label: "D\(dayOffset)", minutesBySubject: minutes)
    }

    /// `minutes` long; ended unless `active`.
    private func session(_ name: String, minutes: Double, active: Bool = false) -> Session {
        let end = start.addingTimeInterval(minutes * 60)
        return Session(subjectID: UUID(), subjectName: name, mode: .open, start: start,
                       end: active ? nil : end, lastHeartbeat: end)
    }

    // MARK: - Labels

    func testStreakLabel() {
        XCTAssertEqual(StatsFormatting.streak(0), "0 days")
        XCTAssertEqual(StatsFormatting.streak(1), "1 day")
        XCTAssertEqual(StatsFormatting.streak(2), "2 days")
        XCTAssertEqual(StatsFormatting.streak(30), "30 days")
    }

    func testPercentIsRoundedToWholeNumbers() {
        XCTAssertEqual(StatsFormatting.percent(0.42), "42%")
        XCTAssertEqual(StatsFormatting.percent(0.4249), "42%")
        XCTAssertEqual(StatsFormatting.percent(0.426), "43%")
        XCTAssertEqual(StatsFormatting.percent(1.0 / 3.0), "33%")
        XCTAssertEqual(StatsFormatting.percent(0.004), "0%")
        XCTAssertEqual(StatsFormatting.percent(0), "0%")
        XCTAssertEqual(StatsFormatting.percent(1), "100%")
    }

    func testPercentAndBarFractionAreClamped() {
        XCTAssertEqual(StatsFormatting.percent(-0.2), "0%")
        XCTAssertEqual(StatsFormatting.percent(1.7), "100%")
        XCTAssertEqual(StatsFormatting.percent(.nan), "0%")
        XCTAssertEqual(StatsFormatting.clampedFraction(0.25), 0.25)
        XCTAssertEqual(StatsFormatting.clampedFraction(-1), 0)
        XCTAssertEqual(StatsFormatting.clampedFraction(2), 1)
        XCTAssertEqual(StatsFormatting.clampedFraction(.infinity), 0)
        XCTAssertEqual(StatsFormatting.clampedFraction(.nan), 0)
    }

    func testRangeCaptions() {
        XCTAssertEqual(StatsRange.allCases.map(StatsFormatting.rangeCaption),
                       ["Last 14 days", "Last 12 weeks", "Last 12 months"])
    }

    func testEmptyMessage() {
        XCTAssertEqual(StatsFormatting.emptyMessage, "No sessions yet — lock in to start tracking.")
    }

    // MARK: - Chart series

    func testChartSubjectsAreOrderedByTotalWithOtherLast() {
        let buckets = [
            bucket(0, ["A": 10, "B": 30]),
            bucket(1, ["B": 5, StatsEngine.otherLabel: 100, "C": 30]),
            bucket(2, [:]),
        ]
        XCTAssertEqual(StatsFormatting.chartSubjects(buckets), ["B", "C", "A", StatsEngine.otherLabel])
    }

    func testChartSubjectsBreakTiesByName() {
        let buckets = [bucket(0, ["Zeta": 5, "Alpha": 5]), bucket(1, ["Mid": 5])]
        XCTAssertEqual(StatsFormatting.chartSubjects(buckets), ["Alpha", "Mid", "Zeta"])
    }

    func testChartSubjectsDropSeriesWithoutMinutes() {
        let buckets = [bucket(0, ["A": 0, StatsEngine.otherLabel: 0]), bucket(1, ["B": 12])]
        XCTAssertEqual(StatsFormatting.chartSubjects(buckets), ["B"])
        XCTAssertEqual(StatsFormatting.chartSubjects([]), [])
    }

    func testAxisLabelsThinOutButKeepTheNewestLabel() {
        let days = (1...14).map { "D\($0)" }
        XCTAssertEqual(StatsFormatting.axisLabels(days, maxCount: 7), ["D2", "D4", "D6", "D8", "D10", "D12", "D14"])
        let months = (1...12).map { "M\($0)" }
        XCTAssertEqual(StatsFormatting.axisLabels(months, maxCount: 7), ["M2", "M4", "M6", "M8", "M10", "M12"])
        XCTAssertEqual(StatsFormatting.axisLabels(months, maxCount: 4), ["M3", "M6", "M9", "M12"])
        XCTAssertEqual(StatsFormatting.axisLabels(["A", "B", "C"], maxCount: 7), ["A", "B", "C"])
        XCTAssertEqual(StatsFormatting.axisLabels(days, maxCount: 0), [])
        XCTAssertEqual(StatsFormatting.axisLabels([], maxCount: 7), [])
    }

    func testMaxAxisLabelsPerRange() {
        XCTAssertEqual(StatsRange.allCases.map(StatsFormatting.maxAxisLabels), [7, 6, 12])
    }

    func testTopSubjectLimitKeepsEverySeriesWithinTheShades() {
        let five = ["A", "B", "C", "D", "E"].map { session($0, minutes: 10) }
        XCTAssertEqual(StatsFormatting.topSubjectLimit(for: [], shades: 5), 5)
        XCTAssertEqual(StatsFormatting.topSubjectLimit(for: five, shades: 5), 5)
        XCTAssertEqual(StatsFormatting.topSubjectLimit(for: five + [session("F", minutes: 1)], shades: 5), 4)
        // Same name twice and an active session do not count as extra subjects.
        let repeated = five + [session("A", minutes: 3), session("G", minutes: 3, active: true)]
        XCTAssertEqual(StatsFormatting.topSubjectLimit(for: repeated, shades: 5), 5)
    }

    // MARK: - Session helpers

    func testTrackedSessionsAndTotalIgnoreActiveSessions() {
        let active = session("CS128", minutes: 50, active: true)
        XCTAssertFalse(StatsFormatting.hasTrackedSessions([]))
        XCTAssertFalse(StatsFormatting.hasTrackedSessions([active]))
        XCTAssertEqual(StatsFormatting.totalSeconds([active]), 0)

        let sessions = [active, session("CS128", minutes: 30), session("MATH241", minutes: 15)]
        XCTAssertTrue(StatsFormatting.hasTrackedSessions(sessions))
        XCTAssertEqual(StatsFormatting.totalSeconds(sessions), 45 * 60, accuracy: 0.001)
    }
}
```

- [ ] **Step 2: Run the StatsFormatting tests and watch them fail**

Run from the repo root:

```bash
cd Tofu && xcodegen generate && xcodebuild -project Tofu.xcodeproj -scheme Tofu -destination 'platform=macOS' test -only-testing:TofuTests/StatsFormattingTests 2>&1 | tail -30
```

Expected: the test target does not compile. The output contains `error: cannot find 'StatsFormatting' in scope` and ends with `** TEST FAILED **`.

- [ ] **Step 3: Implement StatsFormatting**

Create `Tofu/Tofu/Engine/StatsFormatting.swift`:

```swift
import Foundation

/// Pure helpers that turn StatsEngine output into what the Stats screens display.
enum StatsFormatting {
    /// Empty state for the Stats screen and the subject stats section.
    static let emptyMessage = "No sessions yet — lock in to start tracking."

    /// Chart caption per range: "Last 14 days", "Last 12 weeks", "Last 12 months".
    static func rangeCaption(_ range: StatsRange) -> String {
        switch range {
        case .day: return "Last 14 days"
        case .week: return "Last 12 weeks"
        case .month: return "Last 12 months"
        }
    }

    /// "0 days", "1 day", "12 days".
    static func streak(_ days: Int) -> String {
        days == 1 ? "1 day" : "\(max(0, days)) days"
    }

    /// `fraction` clamped to 0...1; NaN and infinities become 0.
    static func clampedFraction(_ fraction: Double) -> Double {
        guard fraction.isFinite else { return 0 }
        return min(max(fraction, 0), 1)
    }

    /// Rounded whole percent: 0.42 -> "42%", 0.426 -> "43%".
    static func percent(_ fraction: Double) -> String {
        "\(Int((clampedFraction(fraction) * 100).rounded()))%"
    }

    /// Chart series order: subjects by total minutes across `buckets` (desc, ties by name),
    /// StatsEngine.otherLabel always last. Series with no minutes are dropped.
    static func chartSubjects(_ buckets: [StatsBucket]) -> [String] {
        var totals: [String: Double] = [:]
        for bucket in buckets {
            for (name, minutes) in bucket.minutesBySubject {
                totals[name, default: 0] += minutes
            }
        }
        let named = totals
            .filter { $0.key != StatsEngine.otherLabel && $0.value > 0 }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map(\.key)
        let hasOther = (totals[StatsEngine.otherLabel] ?? 0) > 0
        return hasOther ? named + [StatsEngine.otherLabel] : named
    }

    /// How many x-axis labels fit in a narrow window: 7 of 14 days, 6 of 12 weeks, all 12 short month names.
    static func maxAxisLabels(_ range: StatsRange) -> Int {
        switch range {
        case .day: return 7
        case .week: return 6
        case .month: return 12
        }
    }

    /// At most `maxCount` evenly spaced x-axis labels, oldest first, always including the newest (last) one,
    /// so 14 day labels do not collide in a narrow window.
    static func axisLabels(_ labels: [String], maxCount: Int) -> [String] {
        guard maxCount > 0 else { return [] }
        guard labels.count > maxCount else { return labels }
        let step = Int((Double(labels.count) / Double(maxCount)).rounded(.up))
        let last = labels.count - 1
        return labels.indices.filter { (last - $0) % step == 0 }.map { labels[$0] }
    }

    /// How many subjects get their own chart series so that, with "Other", there are at most `shades` series:
    /// every subject when they fit, otherwise `shades - 1` plus "Other". Counts ended sessions only.
    static func topSubjectLimit(for sessions: [Session], shades: Int) -> Int {
        let names = Set(sessions.filter { $0.end != nil }.map(\.subjectName))
        return names.count <= shades ? max(0, shades) : max(0, shades - 1)
    }

    /// True when at least one session has ended (active sessions are not tracked yet).
    static func hasTrackedSessions(_ sessions: [Session]) -> Bool {
        sessions.contains { $0.end != nil }
    }

    /// Total duration of ended sessions.
    static func totalSeconds(_ sessions: [Session]) -> TimeInterval {
        sessions.filter { $0.end != nil }.reduce(0) { $0 + $1.duration }
    }
}
```

- [ ] **Step 4: Run the StatsFormatting tests and watch them pass**

Run from the repo root:

```bash
cd Tofu && xcodegen generate && xcodebuild -project Tofu.xcodeproj -scheme Tofu -destination 'platform=macOS' test -only-testing:TofuTests/StatsFormattingTests 2>&1 | tail -30
```

Expected: `Test Suite 'StatsFormattingTests' passed`, `Executed 12 tests, with 0 failures (0 unexpected)` and `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit StatsFormatting**

```bash
cd "$(git rev-parse --show-toplevel)" && git add Tofu/Tofu/Engine/StatsFormatting.swift Tofu/TofuTests/StatsFormattingTests.swift Tofu/Tofu.xcodeproj && git commit -F - <<'EOF'
Add StatsFormatting: chart series order, axis labels, streak/percent texts

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

- [ ] **Step 6: Replace the StatsView placeholder**

Replace the whole content of `Tofu/Tofu/UI/StatsView.swift` with the code below. `import Charts` is all Swift Charts needs: the framework links automatically, so `project.yml` does not change.

```swift
import Charts
import SwiftUI

/// Stats screen (spec §10): range toggle, stacked bar chart, summary cards and per-subject breakdown.
struct StatsView: View {
    let model: AppModel
    @State private var range: StatsRange = .day

    var body: some View {
        let sessions = model.data.sessions
        // Reading engine.now refreshes this view every second while locked; Date() keeps "today" right when idle.
        let stats = StatsEngine(now: max(model.engine.now, Date()))
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Stats").font(Theme.titleFont)
                    Spacer()
                    Picker("Range", selection: $range) {
                        ForEach(StatsRange.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 240)
                }
                if StatsFormatting.hasTrackedSessions(sessions) {
                    let limit = StatsFormatting.topSubjectLimit(for: sessions, shades: Theme.grays.count)
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        Text(StatsFormatting.rangeCaption(range)).font(Theme.captionFont).foregroundStyle(.secondary)
                        StatsStackedChart(buckets: stats.buckets(sessions, range: range, topSubjects: limit),
                                          maxLabels: StatsFormatting.maxAxisLabels(range))
                    }
                    StatsSummaryGrid(summary: stats.summary(sessions))
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        Text("By subject").font(Theme.captionFont).foregroundStyle(.secondary)
                        StatsSubjectBreakdown(shares: stats.shares(sessions))
                    }
                } else {
                    Text(StatsFormatting.emptyMessage)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 240)
                }
            }
            .padding(Theme.Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Stats")
    }
}

/// Cards + 14-day mini chart filtered to one subject (used in SubjectDetailView).
struct SubjectStatsSection: View {
    let model: AppModel
    let subjectID: UUID

    var body: some View {
        let sessions = model.data.sessions.filter { $0.subjectID == subjectID }
        let stats = StatsEngine(now: max(model.engine.now, Date()))
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("Stats").font(Theme.captionFont).foregroundStyle(.secondary)
            if StatsFormatting.hasTrackedSessions(sessions) {
                let summary = stats.summary(sessions)
                LazyVGrid(columns: statsGridColumns, alignment: .leading, spacing: Theme.Space.m) {
                    StatCard(title: "Total", value: TimeFormat.short(StatsFormatting.totalSeconds(sessions)))
                    StatCard(title: "Sessions", value: "\(summary.sessionCount)")
                    StatCard(title: "Average", value: TimeFormat.short(summary.average))
                    StatCard(title: "Streak", value: StatsFormatting.streak(summary.currentStreak))
                }
                Text(StatsFormatting.rangeCaption(.day)).font(Theme.captionFont).foregroundStyle(.secondary)
                StatsDayChart(buckets: stats.buckets(sessions, range: .day))
            } else {
                Text(StatsFormatting.emptyMessage).foregroundStyle(.secondary)
            }
        }
    }
}

/// Adaptive card grid shared by both stats views.
private let statsGridColumns = [GridItem(.adaptive(minimum: 140), spacing: Theme.Space.m, alignment: .top)]

/// X axis with at most `maxLabels` untruncated bucket labels (the newest always shown).
private func bucketAxis(_ buckets: [StatsBucket], maxLabels: Int) -> some AxisContent {
    AxisMarks(values: StatsFormatting.axisLabels(buckets.map(\.label), maxCount: maxLabels)) { value in
        AxisGridLine()
        AxisTick()
        AxisValueLabel(collisionResolution: .disabled) {
            Text(value.as(String.self) ?? "").fixedSize()
        }
    }
}

/// Bars of minutes per period, stacked by subject, one gray per subject ("Other" lightest).
private struct StatsStackedChart: View {
    let buckets: [StatsBucket]
    let maxLabels: Int

    var body: some View {
        let subjects = StatsFormatting.chartSubjects(buckets)
        Chart {
            ForEach(buckets) { bucket in
                ForEach(subjects, id: \.self) { subject in
                    if let minutes = bucket.minutesBySubject[subject], minutes > 0 {
                        BarMark(x: .value("Period", bucket.label), y: .value("Minutes", minutes))
                            .foregroundStyle(by: .value("Subject", subject))
                    }
                }
            }
        }
        .chartXScale(domain: buckets.map(\.label))
        .chartXAxis { bucketAxis(buckets, maxLabels: maxLabels) }
        .chartForegroundStyleScale(domain: subjects, range: subjects.indices.map(Theme.gray(at:)))
        .chartYAxisLabel("min")
        .chartLegend(position: .top, alignment: .leading)
        .overlay {
            if subjects.isEmpty {
                Text("No time tracked in this range").foregroundStyle(.secondary)
            }
        }
        .frame(height: 260)
    }
}

/// Single-series bars (total minutes per day) for the subject detail.
private struct StatsDayChart: View {
    let buckets: [StatsBucket]

    var body: some View {
        Chart(buckets) { bucket in
            BarMark(x: .value("Day", bucket.label), y: .value("Minutes", bucket.totalMinutes))
                .foregroundStyle(Color.primary)
        }
        .chartXScale(domain: buckets.map(\.label))
        .chartXAxis { bucketAxis(buckets, maxLabels: StatsFormatting.maxAxisLabels(.day)) }
        .chartYAxisLabel("min")
        .frame(height: 140)
    }
}

/// The ten summary cards from spec §10.
private struct StatsSummaryGrid: View {
    let summary: StatsSummary

    var body: some View {
        LazyVGrid(columns: statsGridColumns, alignment: .leading, spacing: Theme.Space.m) {
            StatCard(title: "Today", value: TimeFormat.short(summary.today))
            StatCard(title: "This week", value: TimeFormat.short(summary.thisWeek))
            StatCard(title: "Current streak", value: StatsFormatting.streak(summary.currentStreak))
            StatCard(title: "Longest streak", value: StatsFormatting.streak(summary.longestStreak))
            StatCard(title: "Sessions", value: "\(summary.sessionCount)")
            StatCard(title: "Average", value: TimeFormat.short(summary.average))
            StatCard(title: "Longest", value: TimeFormat.short(summary.longest))
            StatCard(title: "Apps blocked", value: "\(summary.blockedAttempts)")
            StatCard(title: "Tabs closed", value: "\(summary.closedTabs)")
            StatCard(title: "Bails", value: "\(summary.bails)")
        }
    }
}

/// One row per subject: name, proportional bar, total time, percent. Sorted by StatsEngine.shares.
private struct StatsSubjectBreakdown: View {
    let shares: [SubjectShare]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            ForEach(shares) { share in
                HStack(spacing: Theme.Space.m) {
                    Text(share.name)
                        .lineLimit(1)
                        .frame(width: 120, alignment: .leading)
                    StatsShareBar(fraction: share.fraction)
                    Text(TimeFormat.short(share.seconds))
                        .monospacedDigit()
                        .frame(width: 72, alignment: .trailing)
                    Text(StatsFormatting.percent(share.fraction))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
            }
        }
    }
}

/// Horizontal bar filled to `fraction` of the available width.
private struct StatsShareBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2).fill(Color.primary.opacity(0.08))
                RoundedRectangle(cornerRadius: 2).fill(Color.primary)
                    .frame(width: proxy.size.width * StatsFormatting.clampedFraction(fraction))
            }
        }
        .frame(height: 8)
    }
}
```

- [ ] **Step 7: Build the app**

Run from the repo root:

```bash
(cd Tofu && xcodegen generate && xcodebuild -project Tofu.xcodeproj -scheme Tofu -configuration Debug -destination 'platform=macOS' -derivedDataPath build/DerivedData build 2>&1 | tail -5)
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 8: Verify the stats screens by hand with demo data**

Run from the repo root:

```bash
open Tofu/build/DerivedData/Build/Products/Debug/Tofu.app
```

1. **Empty state.**
   - With no finished sessions (clear demo data first if needed), **Stats** in the sidebar shows the `Stats` title, the Day/Week/Month picker and `No sessions yet — lock in to start tracking.`
   - If you already have a subject, its detail page shows a `STATS` caption with the same sentence.
2. Open **Settings › Demo** and click **Load demo data**. It shows `N demo sessions loaded` (about 40), and the sidebar lists `CS128` and `MATH241` if you had no subjects.
3. **Day.** Open **Stats** with **Day** selected:
   - `LAST 14 DAYS` caption.
   - A legend with both subject names. In light mode the bigger subject is black and the other dark gray.
   - Stacked bars on most of the last 14 days. A few days may be empty.
   - 7 full x-axis labels, ending with today (e.g. `Oct 10`).
   - A y-axis titled `min`.
4. **Week.** Click **Week**:
   - `LAST 12 WEEKS` caption.
   - Bars in the last 5 or so weeks; the earlier weeks are empty.
   - 6 labels, ending with the start of this week.
5. **Month.** Click **Month**:
   - `LAST 12 MONTHS` caption.
   - Bars in this month and the previous one (and possibly one more).
   - All 12 month abbreviations under the axis.
6. **Cards.** Below the chart are ten cards: `TODAY`, `THIS WEEK`, `CURRENT STREAK`, `LONGEST STREAK`, `SESSIONS`, `AVERAGE`, `LONGEST`, `APPS BLOCKED`, `TABS CLOSED`, `BAILS`.
   - The streak cards read like `3 days` (or `1 day`).
   - `SESSIONS` is at least N from step 2. It is more if Task 14's manual run left real sessions.
   - `TODAY` and `CURRENT STREAK` can be `0m` / `0 days` early in the morning. Every other card is non-zero.
7. **By subject.** There is one row per subject with sessions (at least `CS128` and `MATH241`), each with:
   - a black bar proportional to its share;
   - a total like `22h 35m`;
   - a percent.

   The percents add up to 100% (±1 per row from rounding).
8. **Subject page.** Click **CS128** in the sidebar. Under the subject summary there are:
   - a `STATS` caption with four cards: `TOTAL`, `SESSIONS`, `AVERAGE`, `STREAK`;
   - a `LAST 14 DAYS` mini chart with black bars.
9. **Narrow window.** Drag the window to its minimum width:
   - the cards reflow into fewer columns;
   - the x-axis labels stay whole (no `Se…`).
10. **Dark mode.** Switch to dark mode:
    - the bars become white and light grays on black;
    - nothing anywhere is colored.
11. **Clear.** Go to **Settings › Demo** and click **Clear demo data**. Stats returns to the empty state, unless you have real sessions.

Quit the app when done.

- [ ] **Step 9: Run the full test suite**

Run from the repo root:

```bash
cd Tofu && xcodegen generate && xcodebuild -project Tofu.xcodeproj -scheme Tofu -destination 'platform=macOS' test 2>&1 | tail -30
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 10: Commit StatsView**

```bash
cd "$(git rev-parse --show-toplevel)" && git add Tofu/Tofu/UI/StatsView.swift Tofu/Tofu.xcodeproj && git commit -F - <<'EOF'
Build Stats: stacked day/week/month chart, summary cards, subject breakdown

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

Expected: `git status --short` prints nothing.

---

### Task 17: README, full test run, release build and demo checklist

This task:

1. replaces the old GrokBot `README.md` at the repo root with documentation for the app;
2. runs the whole test suite and checks that every test class passed;
3. builds the Release app;
4. walks through the manual demo checklist from spec §13: the spec §1 success criteria, steps 1–8, plus the Automation prompt, the Discord Test button and Cmd+Q recovery.

**Files:**
- Modify (rewrite entirely): `README.md`

**Interfaces:**
- Consumes:
  - every task's finished product;
  - the Settings texts from Task 15: **Post lock-ins to Discord**, **Discord setup › Application ID**, **Invite the bot to a server**, **Request access**, **Test connection**;
  - the toast texts from Task 10: `🔒 <App> is blocked during <Subject>`, `Closed <host> — not part of <Subject>`, `Saved: <duration> on <Subject>`;
  - the Discord texts from Task 5.
- Produces: `README.md`. No code.

- [ ] **Step 1: Rewrite README.md**

Replace the whole content of `README.md` at the repo root with the following. It removes every GrokBot section.

````markdown
# Tofu

**Lock in on a subject, and your Mac turns into a study room.**

Tofu is a native macOS app. One click hides every other app and opens your study sites in Google Chrome, tiled in the layout you picked. Distractions are pushed away the moment they appear, your friends on Discord see that you're locked in, and the app tracks how long you actually stayed focused.

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
  - Chrome, Finder and Tofu are always allowed.
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
git clone https://github.com/zyin422/tofu.git
cd tofu/Tofu
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

## Permissions

The app needs exactly one permission: **Automation → Google Chrome**.

- **What it's for:**
  - opening and arranging the study windows;
  - reading tab URLs and closing off-topic tabs;
  - minimizing and restoring your own windows.
- **When macOS asks:** once, with "Tofu wants access to control Google Chrome". To get the prompt out of the way early, use **Settings › Chrome › Request access**.

The app does **not** need Accessibility, Screen Recording, Full Disk Access or notification permission. It never scripts System Events.

- **Denied by accident?** Turn it back on in **System Settings › Privacy & Security › Automation › Tofu › Google Chrome**. A lock-in without it still hides and blocks apps.
- **Unsandboxed by design.** Hiding other apps does not work inside the App Sandbox, so the app can't ship on the Mac App Store. It is built locally and signed ad hoc (`CODE_SIGN_IDENTITY = -`).
- **Rebuilds can bring the prompt back.** An ad-hoc signature changes on every rebuild, so macOS may ask for Chrome access again. To reset the answer, run `tccutil reset AppleEvents com.tofu.app`.

## Discord setup

Discord bots can't join group DMs, so the app posts to one text channel in every server the bot is in.

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
| Discord bot token | The Keychain: a generic password with service `com.tofu.discord` and account `bot-token`. It is never written to JSON or logs. |
| Discord Application ID (only used for the invite link) | App preferences, key `discordAppID` |

To start over, quit the app and delete `~/Library/Application Support/Tofu/`. To remove the token, use **Settings › Discord › Remove**.

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
tofu/
├── README.md
├── docs/superpowers/        design spec and implementation plan
├── *.pdf                    Code Ada 2026 packet and presentation guidelines
└── Tofu/
    ├── project.yml          XcodeGen spec (source of truth for the Xcode project)
    ├── Tofu.xcodeproj/
    ├── Tofu/
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
    └── TofuTests/   XCTest suites for every pure unit, plus SessionEngine with fakes
```

Side effects sit behind small `@MainActor` protocols: `WorkspaceControlling`, `AppBlocking`, `ChromeControlling`, `Toasting`, `Announcing` and `WindowPresenting`. So the whole lock-in lifecycle is tested without touching real apps, Chrome or Discord.

## Tests

```bash
cd Tofu && xcodegen generate && \
  xcodebuild -project Tofu.xcodeproj -scheme Tofu -destination 'platform=macOS' test 2>&1 | tail -30
```

The run ends with `** TEST SUCCEEDED **`. No test touches the network, Chrome, other apps or your real data:
- store tests write to a temporary folder;
- Keychain tests use their own service, `com.tofu.tests`.
````

- [ ] **Step 2: Check the README against the repo**

Run from the repo root:

```bash
grep -ciE "grok|launchpad|ledger|mirror" README.md; ls Tofu/Tofu
```

Expected:
- First line: `0` (no GrokBot leftovers).
- Then the folders `App`, `Discord`, `Engine`, `Models`, `Persistence`, `Resources`, `System`, `UI`. These match the **Project structure** tree.

If a folder from the tree is missing, or an extra one exists, update the tree in `README.md` to match.

- [ ] **Step 3: Run the full test suite and check every test class passed**

Run from the repo root:

```bash
cd Tofu && mkdir -p build && xcodegen generate && xcodebuild -project Tofu.xcodeproj -scheme Tofu -destination 'platform=macOS' test 2>&1 | tee build/test.log | tail -5 \
  && grep -oE "Test Suite '[A-Za-z]+Tests' passed" build/test.log | sed -E "s/Test Suite '([A-Za-z]+)' passed/\1/" | sort -u > build/passed-suites.txt \
  && cat TofuTests/*.swift | grep -oE "class [A-Za-z]+Tests: XCTestCase" | awk '{print $2}' | tr -d ':' | sort -u > build/expected-suites.txt \
  && echo "--- passed suites:" && cat build/passed-suites.txt \
  && echo "--- declared but not passed:" && comm -23 build/expected-suites.txt build/passed-suites.txt \
  && grep -E "Executed [0-9]+ tests, with [0-9]+ failures" build/test.log | tail -1
```

Expected:

- The `tail -5` output includes `** TEST SUCCEEDED **` (xcodebuild may print `Testing started` after it).
- Under `--- passed suites:` there is one line per XCTest class, alphabetically. That includes these classes:

  | Task | Classes |
  |---|---|
  | 1–2 | `SmokeTests`, `ModelsTests`, `StoreTests`, `KeychainTests` |
  | 3 | `LayoutEngineTests`, `ScreenGeometryTests` |
  | 4 | `DomainMatcherTests` |
  | 5 | `TimeFormatTests`, `DiscordMessagesTests`, `ChannelPickerTests` |
  | 6 | `DiscordClientTests` |
  | 7 | `BlockPolicyTests` |
  | 8 | `ChromeScriptsTests`, `ChromeControllerTests` |
  | 9 | `ToastLayoutTests` |
  | 10 | `SessionEngineTests` |
  | 11 | `StatsEngineTests`, `DemoDataTests` |
  | 12 | `AppModelTests`, `DiscordAnnouncerTests` |
  | 13 | `AppCatalogTests`, `SubjectValidatorTests`, `LockInOptionTests` |
  | 14 | `MiniTimerLayoutTests`, `LockedLayoutTests` |
  | 15 | `SettingsStatusTests` |
  | 16 | `StatsFormattingTests` |

- Under `--- declared but not passed:` there is **nothing**. That comparison reads the class names straight from the test files, so it is the authoritative check, even if an earlier task named a class differently from the table.
- There are 27 classes, and the last line reads `Executed 277 tests, with 0 failures (0 unexpected) …`.

Review Focus 1–5 are all covered by this run:

| Review Focus | Covered by |
|---|---|
| 1 | `BlockPolicyTests` |
| 2 | `DomainMatcherTests` |
| 3 | `StoreTests` and `SessionEngineTests` |
| 4 | `SessionEngineTests` |
| 5 | `DiscordClientTests` and `DiscordAnnouncerTests` |

If anything fails, fix it in the task that owns the failing unit before continuing.

- [ ] **Step 4: Build the Release app**

Run from the repo root:

```bash
cd Tofu && xcodebuild -project Tofu.xcodeproj -scheme Tofu -configuration Release -destination 'platform=macOS' -derivedDataPath build/DerivedData build 2>&1 | tail -3 \
  && APP=build/DerivedData/Build/Products/Release/Tofu.app \
  && codesign -dv "$APP" 2>&1 | grep -E "^(Identifier|Signature)" \
  && plutil -p "$APP/Contents/Info.plist" | grep -E "CFBundleIdentifier|NSAppleEventsUsageDescription|LSMinimumSystemVersion" \
  && codesign -d --entitlements - "$APP" 2>&1 | grep -c "app-sandbox"
```

Expected:

```
** BUILD SUCCEEDED **
Identifier=com.tofu.app
Signature=adhoc
  "CFBundleIdentifier" => "com.tofu.app"
  "LSMinimumSystemVersion" => "14.0"
  "NSAppleEventsUsageDescription" => "Tofu opens and arranges your study sites in Google Chrome and closes off-topic tabs while you're locked in."
0
```

The final `0` means the app has no sandbox entitlement.

- [ ] **Step 5: Prepare the demo Mac**

Use the Release app from Step 4 for every check below. Prepare the Mac:

1. **Apps to hide.** Open Notes, Messages and (if installed) the Discord desktop app, so there is something to hide.
2. **Chrome.** Launch Google Chrome with your normal profile and leave one ordinary window open. A cold Chrome or the profile picker makes window creation retry.
3. **Discord server.**
   - The bot from the README's Discord setup is in a server.
   - The server has a `#lock-in` channel.
   - Keep the channel visible on your phone or another computer.
4. **Start the app.** Terminal and Xcode will be hidden during each lock-in; that is expected. Start the app from Finder or with:

   ```bash
   open Tofu/build/DerivedData/Build/Products/Release/Tofu.app
   ```

- [ ] **Step 6: Check the Automation prompt and the Discord Test button**

1. **Fresh Automation state.** Quit the app. Reset its Automation answer only, then relaunch:

   ```bash
   tccutil reset AppleEvents com.tofu.app && open Tofu/build/DerivedData/Build/Products/Release/Tofu.app
   ```

   Expected: `Successfully reset AppleEvents approval status for com.tofu.app`.
2. **Request access.**
   1. Open **Settings**. **Automation** shows `Not checked yet`.
   2. Click **Request access**. The status shows `Waiting for macOS…`, then macOS asks "“Tofu” wants access to control “Google Chrome”…".
   3. Allow it. The status reads `Chrome control allowed`.
   4. Click **Request access** again. It answers `Chrome control allowed` at once, with no prompt.
3. **Discord.**
   1. Paste the real bot token, click **Save**, and turn on **Post lock-ins to Discord**.
   2. Click **Test connection**. It shows `Connected as <bot name> · <n> servers`, or `· 1 server`.
   3. Set **Display name** to the name you want friends to see, e.g. `Alex`.

- [ ] **Step 7: Run spec §1 success criteria 1–8**

Each item lists the exact thing to observe.

1. **Create the subject.**
   1. Click **+** in the sidebar.
   2. Fill in:
      - name `CS128`;
      - preset **Left / Right**;
      - site 1 `cs128.org`;
      - site 2 `Piazza.com/class/demo`, with an uppercase P and no scheme, on purpose for Review Focus 2.
   3. Leave allowed apps empty and save.

   `CS128` appears in the sidebar. Its detail page shows the Left / Right thumbnail, both sites and the LOCK IN button.
2. **Lock in.**
   1. Click **LOCK IN** and choose **25** minutes, then confirm. Within a few seconds:
      - Notes, Messages, Discord (and Terminal) disappear. They are hidden, not quit: they keep their Dock dots.
      - Chrome's existing window is minimized into the Dock.
      - Two new Chrome windows fill the left and right halves of the main screen, between the menu bar and the Dock. The left loads `https://cs128.org`; the right loads `https://piazza.com/class/demo` (Piazza may redirect to its login page).
      - The main window is gone. A small floating timer at the top center shows `CS128` and counts down from `25:00`.
3. **Discord start message.** `#lock-in` receives `🔒 Alex is locked in on CS128 (goal 25m)`, with the name and subject in bold.
4. **Blocked apps.**
   1. Click Discord in the Dock. It flashes for at most a moment and disappears again.
   2. A black toast (white in dark mode) appears top-right, below the menu bar: `🔒 Discord is blocked during CS128`.
   3. Wait 3 seconds, then click the Discord Dock icon 3 times within 2 seconds:
      - Discord is hidden every time.
      - Only **one** new toast appears, because only one attempt is counted (Review Focus 1).
   4. Cmd-Tab to Notes. It is hidden again, and the toast `🔒 Notes is blocked during CS128` appears.
   5. Click the mini timer's body. The main window shows the giant timer and the counters: **3** apps blocked, **0** tabs closed. If it shows 4, the 3 clicks took longer than 2 seconds.
5. **Blocked site.**
   1. In the left Chrome window press ⌘T and wait 5 seconds. The empty new tab stays open (it is never closed).
   2. Type `youtube.com` and press Return. Within about 2 seconds the tab closes, and the toast `Closed youtube.com — not part of CS128` appears.
   3. Open `www.piazza.com/class/other` in a new tab. It stays open: `www.` and subdomains of `piazza.com` are allowed (Review Focus 2). Piazza may redirect to its login page, which is still on `piazza.com`.
   4. Open `notpiazza.com`. It is closed, with the toast `Closed notpiazza.com — not part of CS128`.
   5. The tabs-closed counter in the main window now shows **2**.
6. **End early (bail).**
   1. Click **End** in the main window, or **✕** on the mini timer, before 25 minutes have passed.
   2. The give-up sheet shows the phrase `I give up on CS128` and the line `Ending early will be posted to Discord.`. **Bail** is disabled.
   3. Type `i give up on cs128  `, in lowercase and with trailing spaces. **Bail** becomes enabled (Review Focus 4).
   4. Click **Cancel** first. The session continues and the timer keeps counting.
   5. Click **End** again, type the phrase and click **Bail**.
   6. `#lock-in` receives `🏳️ Alex bailed on CS128 after <n>m (goal 25m) · tried other apps <attempts>×`.
   7. The toast `Saved: <n>m on CS128` appears.
7. **Restore.** Right after the bail:
   - Notes, Messages, Discord and Terminal come back where they were.
   - Chrome's originally minimized window comes back out of the Dock.
   - The two study windows stay open.
   - The main window returns to its pre-lock size and position.
8. **Stats.**
   1. Open **Settings › Demo** and click **Load demo data**. Open **Stats**: Day, Week and Month each show stacked bars in grays, and the ten summary cards are filled in.
   2. `SESSIONS` and `BAILS` include the real session you just bailed on. Clear demo data: `SESSIONS` now counts only your real sessions (at least 1), and `BAILS` is at least 1.
   3. Load demo data again for the demo itself.

**Goal completion.** This is optional, but recommended for Review Focus 4.

1. Lock in on `CS128` with a **custom** goal of **1** minute.
2. At `00:00`, the session ends on its own:
   - no give-up sheet appears;
   - exactly one `✅ Alex locked in on CS128 for 1m · tried other apps 0× · closed 0 tabs` message is posted;
   - the hidden apps return.

- [ ] **Step 8: Check Cmd+Q and crash recovery mid-session**

1. **Cmd+Q.**
   1. Lock in on `CS128` with **Open-ended**. Notes and Messages are hidden. Wait at least 1 minute.
   2. Click the mini timer's body to bring the app forward, then press **⌘Q**. Immediately:
      - Notes, Messages and Discord reappear;
      - Chrome's minimized window is restored;
      - **no** Discord message is posted.
   3. Relaunch the app and run:

      ```bash
      grep -c '"interrupted"' ~/Library/Application\ Support/Tofu/store.json
      ```

      Expected: `1` or more.
   4. **Stats › SESSIONS** went up by one.
2. **Crash** (optional, Review Focus 3).
   1. Quit the app. In Terminal, run:

      ```bash
      (sleep 90; pkill -9 -x Tofu) &
      ```

   2. Within 90 seconds, launch the app and lock in **Open-ended**. When the timer passes about 1:10, the app is killed. The hidden apps stay hidden; that is documented in Known limitations. Bring them back from the Dock.
   3. Relaunch the app. The session appears in **Stats** and **no** Discord message is posted. Its time ends at its last 30-second heartbeat, so it counts as `1m` (or `0m` if the kill came before the 1:00 heartbeat).

- [ ] **Step 9: Commit the README**

```bash
cd "$(git rev-parse --show-toplevel)" && git add README.md && git commit -F - <<'EOF'
Rewrite README for the macOS lock-in app

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

Expected:
- `git status --short` prints nothing. Everything under `Tofu/build/` is ignored.
- `git log --oneline -3` shows this commit on top of the Task 16 commits.

