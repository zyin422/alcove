import XCTest
@testable import Tofu

final class AutoLaunchTests: XCTestCase {
    func testAutostartPlistStructure() {
        let appURL = URL(fileURLWithPath: "/Applications/Tofu.app")
        let plist = AutoLaunchManager.autostartPlist(appURL: appURL)
        XCTAssertTrue(plist.contains("<string>com.tofu.autostart</string>"))
        XCTAssertTrue(plist.contains("<string>/usr/bin/open</string>"))
        XCTAssertTrue(plist.contains("<string>/Applications/Tofu.app</string>"))
        XCTAssertTrue(plist.contains("<key>RunAtLoad</key>"))
        XCTAssertTrue(plist.contains("<true/>"))
    }

    func testGuardianScriptAndPlistStructure() {
        let appURL = URL(fileURLWithPath: "/Users/test/Applications/Tofu.app")
        let script = AutoLaunchManager.guardianScript(appURL: appURL)
        XCTAssertTrue(script.contains("pgrep -x Tofu"))
        XCTAssertTrue(script.contains("app='/Users/test/Applications/Tofu.app'"))
        XCTAssertTrue(script.contains("open -g \"$app\""))
        XCTAssertTrue(script.contains("hour=$(date +%-H)"))
        XCTAssertTrue(script.contains("\"$hour\" -ge 4"))

        let plist = AutoLaunchManager.guardianPlist(scriptPath: "/tmp/day-guardian.sh")
        XCTAssertTrue(plist.contains("<string>com.tofu.dayguardian</string>"))
        XCTAssertTrue(plist.contains("<string>/tmp/day-guardian.sh</string>"))
        XCTAssertTrue(plist.contains("<key>KeepAlive</key>"))
    }

    func testXmlEscapingInPlist() {
        let appURL = URL(fileURLWithPath: "/Applications/T&O<F>U.app")
        let plist = AutoLaunchManager.autostartPlist(appURL: appURL)
        XCTAssertTrue(plist.contains("T&amp;O&lt;F&gt;U.app"))
    }

    func testAppSettingsDefaultsAndCoding() throws {
        let defaults = AppSettings()
        XCTAssertTrue(defaults.autoLaunchAtLogin)
        XCTAssertTrue(defaults.dayGuardianEnabled)

        // Test decoding json without the new keys (backward compatibility)
        let legacyJSON = """
        {
            "displayName": "TestUser",
            "discordEnabled": false,
            "giveUpTemplate": "I give up"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(AppSettings.self, from: legacyJSON)
        XCTAssertTrue(decoded.autoLaunchAtLogin)
        XCTAssertTrue(decoded.dayGuardianEnabled)
        XCTAssertEqual(decoded.displayName, "TestUser")

        // Test encoding and round-tripping
        var modified = defaults
        modified.autoLaunchAtLogin = false
        modified.dayGuardianEnabled = false
        let data = try JSONEncoder().encode(modified)
        let roundTripped = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertFalse(roundTripped.autoLaunchAtLogin)
        XCTAssertFalse(roundTripped.dayGuardianEnabled)
    }

    @MainActor
    func testAppModelSyncCall() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = Store(fileURL: dir.appendingPathComponent("store.json"))
        let model = AppModel(store: store)
        XCTAssertTrue(model.data.settings.autoLaunchAtLogin)
        XCTAssertTrue(model.data.settings.dayGuardianEnabled)

        model.updateSettings {
            $0.autoLaunchAtLogin = false
            $0.dayGuardianEnabled = false
        }
        XCTAssertFalse(model.data.settings.autoLaunchAtLogin)
        XCTAssertFalse(model.data.settings.dayGuardianEnabled)
    }
}
