import Foundation

/// Manages launch-at-login and daytime watchdog LaunchAgents in ~/Library/LaunchAgents/
/// to eliminate voluntary initiation friction and prevent avoidance.
enum AutoLaunchManager {
    static let autostartLabel = "com.alcove.autostart"
    static let guardianLabel = "com.alcove.dayguardian"

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    static var launchAgentsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
    }

    static var autostartPlistURL: URL {
        launchAgentsDirectory.appendingPathComponent("\(autostartLabel).plist")
    }

    static var guardianPlistURL: URL {
        launchAgentsDirectory.appendingPathComponent("\(guardianLabel).plist")
    }

    static var guardianScriptURL: URL {
        Store.defaultURL().deletingLastPathComponent().appendingPathComponent("day-guardian.sh")
    }

    static func autostartPlist(appURL: URL) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key>
          <string>\(autostartLabel)</string>
          <key>ProgramArguments</key>
          <array>
            <string>/usr/bin/open</string>
            <string>\(xml(appURL.path))</string>
          </array>
          <key>RunAtLoad</key>
          <true/>
        </dict>
        </plist>
        """
    }

    static func guardianScript(appURL: URL) -> String {
        """
        #!/bin/bash
        app=\(shell(appURL.path))
        while true; do
          hour=$(date +%-H)
          if [ "$hour" -ge 7 ] && [ "$hour" -lt 23 ]; then
            if ! pgrep -x Alcove >/dev/null 2>&1; then
              open -g "$app"
            fi
          fi
          sleep 15
        done
        """
    }

    static func guardianPlist(scriptPath: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key>
          <string>\(guardianLabel)</string>
          <key>ProgramArguments</key>
          <array>
            <string>/bin/bash</string>
            <string>\(xml(scriptPath))</string>
          </array>
          <key>RunAtLoad</key>
          <true/>
          <key>KeepAlive</key>
          <true/>
          <key>ThrottleInterval</key>
          <integer>10</integer>
        </dict>
        </plist>
        """
    }

    static func setAutoLaunch(enabled: Bool, appURL: URL = Bundle.main.bundleURL) {
        guard !isRunningTests else { return }
        let fm = FileManager.default
        if enabled {
            try? fm.createDirectory(at: launchAgentsDirectory, withIntermediateDirectories: true)
            try? autostartPlist(appURL: appURL).write(to: autostartPlistURL, atomically: true, encoding: .utf8)
            let domain = "gui/\(getuid())"
            run("/bin/launchctl", ["bootout", "\(domain)/\(autostartLabel)"])
            run("/bin/launchctl", ["bootstrap", domain, autostartPlistURL.path])
        } else {
            let domain = "gui/\(getuid())"
            run("/bin/launchctl", ["bootout", "\(domain)/\(autostartLabel)"])
            try? fm.removeItem(at: autostartPlistURL)
        }
    }

    static func setDayGuardian(enabled: Bool, appURL: URL = Bundle.main.bundleURL) {
        guard !isRunningTests else { return }
        let fm = FileManager.default
        if enabled {
            try? fm.createDirectory(at: launchAgentsDirectory, withIntermediateDirectories: true)
            try? fm.createDirectory(at: guardianScriptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let script = guardianScript(appURL: appURL)
            try? script.write(to: guardianScriptURL, atomically: true, encoding: .utf8)
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: guardianScriptURL.path)
            try? guardianPlist(scriptPath: guardianScriptURL.path).write(to: guardianPlistURL, atomically: true, encoding: .utf8)
            let domain = "gui/\(getuid())"
            run("/bin/launchctl", ["bootout", "\(domain)/\(guardianLabel)"])
            run("/bin/launchctl", ["bootstrap", domain, guardianPlistURL.path])
        } else {
            let domain = "gui/\(getuid())"
            run("/bin/launchctl", ["bootout", "\(domain)/\(guardianLabel)"])
            try? fm.removeItem(at: guardianPlistURL)
            try? fm.removeItem(at: guardianScriptURL)
        }
    }

    private static func xml(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func shell(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    @discardableResult
    private static func run(_ launchPath: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return 1
        }
    }
}
