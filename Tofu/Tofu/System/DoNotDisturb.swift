import AppKit
import Intents

/// Turns Do Not Disturb on for a work block and off again when that block ends.
@MainActor protocol DoNotDisturbControlling: AnyObject {
    /// Called once the block is actually running (windows, browser, and app blocking are up).
    func beginBlock()
    /// Called when the block ends, including an interrupted quit. A break does not call this.
    func endBlock()
}

/// What to do with Do Not Disturb at the start of a block.
enum DoNotDisturbPlan: Equatable {
    /// Shortcuts are installed and no Focus is on. Turn Do Not Disturb on, and off when the block ends.
    case manage
    /// A Focus is already on. Leave it, including when the block ends.
    case alreadyOn
    /// The On and Off shortcuts are not both installed yet.
    case needsInstall

    static let onName = "Tofu Do Not Disturb On"
    static let offName = "Tofu Do Not Disturb Off"
    static let modeIdentifier = "com.apple.donotdisturb.mode.default"
    /// Shown once ever, the first time a block finds the shortcuts missing. Shortcuts itself is only opened from
    /// Settings › Do Not Disturb, never on its own.
    static let setupHint = "Do Not Disturb isn't set up yet. Add its shortcuts in Settings › Do Not Disturb."
    /// UserDefaults flag: the setup hint was shown (or the user already used the Settings button).
    static let hintShownKey = "doNotDisturbSetupHintShown"
    static let runFailedMessage = "Shortcuts didn’t turn on Do Not Disturb. In Shortcuts settings, allow running scripts, then start the block again."

    static func decide(installed: Set<String>, focusIsOn: Bool) -> DoNotDisturbPlan {
        guard installed.contains(onName), installed.contains(offName) else { return .needsInstall }
        return focusIsOn ? .alreadyOn : .manage
    }

    /// Unsigned shortcut body. `enabled` true turns Do Not Disturb on until something turns it off.
    static func workflow(name: String, enabled: Bool) -> [String: Any] {
        var parameters: [String: Any] = [
            "Enabled": enabled,
            "FocusModes": [
                "DisplayString": "Do Not Disturb",
                "Identifier": modeIdentifier,
            ],
        ]
        if enabled { parameters["AssertionType"] = "Turned Off" }
        return [
            "WFWorkflowName": name,
            "WFWorkflowMinimumClientVersion": 1113,
            "WFWorkflowMinimumClientVersionString": "1113",
            "WFWorkflowClientVersion": "2600.0.1",
            "WFWorkflowClientRelease": "4.0",
            "WFWorkflowIcon": [
                "WFWorkflowIconGlyphNumber": 59511,
                "WFWorkflowIconStartColor": 4282601983,
            ],
            "WFWorkflowImportQuestions": [String](),
            "WFWorkflowTypes": [String](),
            "WFWorkflowInputContentItemClasses": [String](),
            "WFWorkflowOutputContentItemClasses": [String](),
            "WFWorkflowActions": [[
                "WFWorkflowActionIdentifier": "is.workflow.actions.dnd.set",
                "WFWorkflowActionParameters": parameters,
            ] as [String: Any]],
        ]
    }
}

/// Reads the shortcut list, runs a shortcut, and signs the two Tofu shortcuts for the user to add.
struct DoNotDisturbClient {
    var shortcutNames: () -> Set<String>
    var focusIsOn: () -> Bool
    var run: (String) -> Bool
    var install: () -> Bool
    var notify: (String) -> Void

    static func live(notify: @escaping (String) -> Void) -> DoNotDisturbClient {
        DoNotDisturbClient(
            shortcutNames: { DoNotDisturbShortcuts.names() },
            focusIsOn: { DoNotDisturbShortcuts.focusIsOn() },
            run: { DoNotDisturbShortcuts.run($0) },
            install: { DoNotDisturbShortcuts.install() },
            notify: notify)
    }
}

/// Talks to the Shortcuts app. A third-party Mac app cannot set Focus itself; Shortcuts can.
enum DoNotDisturbShortcuts {
    static func names() -> Set<String> {
        let output = command(["list"]).output
        let lines = output.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        return Set(lines.filter { !$0.isEmpty })
    }

    /// True only after the user has allowed Focus status and some Focus is on.
    /// An unanswered prompt reports "off", which would make a block turn off a Focus it did not start.
    static func focusIsOn() -> Bool {
        let center = INFocusStatusCenter.default
        guard center.authorizationStatus == .authorized else { return false }
        return center.focusStatus.isFocused == true
    }

    static func requestFocusStatusIfNeeded() {
        let center = INFocusStatusCenter.default
        guard center.authorizationStatus == .notDetermined else { return }
        center.requestAuthorization { _ in }
    }

    @discardableResult
    static func run(_ name: String) -> Bool {
        command(["run", name]).ok
    }

    /// True when both Tofu shortcuts are in the user's Shortcuts library. Runs `shortcuts list`: call off the main thread.
    static func isInstalled() -> Bool {
        let installed = names()
        return installed.contains(DoNotDisturbPlan.onName) && installed.contains(DoNotDisturbPlan.offName)
    }

    /// Signs both shortcuts and opens them so Shortcuts can ask the user to add them. Returns true when both opened.
    /// Only Settings › Do Not Disturb calls this, on a click. Call off the main thread.
    static func install() -> Bool {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("tofu-do-not-disturb", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return false
        }
        var opened: [URL] = []
        for (name, enabled) in [(DoNotDisturbPlan.onName, true), (DoNotDisturbPlan.offName, false)] {
            guard let signed = sign(name: name, enabled: enabled, in: directory) else { continue }
            opened.append(signed)
        }
        guard opened.count == 2 else { return false }
        var didOpen = true
        DispatchQueue.main.sync {
            for url in opened {
                didOpen = NSWorkspace.shared.open(url) && didOpen
            }
        }
        return didOpen
    }

    private static func sign(name: String, enabled: Bool, in directory: URL) -> URL? {
        let slug = enabled ? "on" : "off"
        let unsigned = directory.appendingPathComponent("\(slug).shortcut")
        let signed = directory.appendingPathComponent("\(slug).signed.shortcut")
        guard let data = try? PropertyListSerialization.data(
            fromPropertyList: DoNotDisturbPlan.workflow(name: name, enabled: enabled),
            format: .binary, options: 0) else { return nil }
        do {
            try data.write(to: unsigned)
        } catch {
            return nil
        }
        let result = command(["sign", "--mode", "anyone", "--input", unsigned.path, "--output", signed.path])
        guard result.ok, FileManager.default.fileExists(atPath: signed.path) else { return nil }
        return signed
    }

    private static func command(_ arguments: [String]) -> (ok: Bool, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return (false, "")
        }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return (process.terminationStatus == 0, output)
    }
}

/// Turns Do Not Disturb on when a work block starts and off when that block ends.
/// The shortcut work happens off the main thread so lock-in does not wait on Shortcuts.
@MainActor final class ShortcutDoNotDisturb: DoNotDisturbControlling {
    private let client: DoNotDisturbClient
    /// Remembers across launches that the setup hint was shown.
    private let defaults: UserDefaults
    private var generation = 0
    private var ownsOff = false
    private var didWarnRun = false

    init(notify: @escaping (String) -> Void) {
        self.client = .live(notify: notify)
        self.defaults = .standard
    }

    init(client: DoNotDisturbClient, defaults: UserDefaults = .standard) {
        self.client = client
        self.defaults = defaults
    }

    func beginBlock() {
        generation += 1
        let token = generation
        ownsOff = false
        DoNotDisturbShortcuts.requestFocusStatusIfNeeded()
        Task { await self.performBegin(token: token) }
    }

    func endBlock() {
        generation += 1
        let shouldOff = ownsOff
        ownsOff = false
        guard shouldOff else { return }
        let run = client.run
        Task.detached {
            run(DoNotDisturbPlan.offName)
        }
    }

    private func performBegin(token: Int) async {
        let snapshot = await readSnapshot()
        guard token == generation else { return }
        switch DoNotDisturbPlan.decide(installed: snapshot.names, focusIsOn: snapshot.focusIsOn) {
        case .needsInstall:
            hintOnce()
            await watchUntilInstalled(token: token)
        case .alreadyOn:
            break
        case .manage:
            await turnOn(token: token)
        }
    }

    /// Points to Settings the first time a block finds the shortcuts missing, then never again (even after relaunch).
    /// Never opens Shortcuts: that only happens from the Settings button.
    private func hintOnce() {
        guard !defaults.bool(forKey: DoNotDisturbPlan.hintShownKey) else { return }
        defaults.set(true, forKey: DoNotDisturbPlan.hintShownKey)
        client.notify(DoNotDisturbPlan.setupHint)
    }

    /// If the user adds the shortcuts while this block is still running, turn Do Not Disturb on for it.
    private func watchUntilInstalled(token: Int) async {
        for _ in 0..<30 {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard token == generation else { return }
            let snapshot = await readSnapshot()
            switch DoNotDisturbPlan.decide(installed: snapshot.names, focusIsOn: snapshot.focusIsOn) {
            case .needsInstall:
                continue
            case .alreadyOn:
                return
            case .manage:
                await turnOn(token: token)
                return
            }
        }
    }

    private func turnOn(token: Int) async {
        guard token == generation else { return }
        let run = client.run
        let ok = await Task.detached { run(DoNotDisturbPlan.onName) }.value
        guard token == generation else {
            if ok {
                _ = await Task.detached { run(DoNotDisturbPlan.offName) }.value
            }
            return
        }
        if ok {
            ownsOff = true
        } else if !didWarnRun {
            didWarnRun = true
            client.notify(DoNotDisturbPlan.runFailedMessage)
        }
    }

    private func readSnapshot() async -> (names: Set<String>, focusIsOn: Bool) {
        let focused = client.focusIsOn()
        let list = client.shortcutNames
        let names = await Task.detached { list() }.value
        return (names, focused)
    }
}
