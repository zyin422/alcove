import Foundation

/// While a block is running, a killed Alcove process is opened again. macOS always allows Force Quit;
/// this is what makes that not an exit from the block. The launch agent is not installed from tests.
enum BlockGuard {
    static let label = "com.alcove.blockguard"

    private static var enabled: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
    }

    private static var directory: URL {
        Store.defaultURL().deletingLastPathComponent()
    }

    static var flagURL: URL { directory.appendingPathComponent("block-open") }
    private static var appPathURL: URL { directory.appendingPathComponent("block-app-path") }
    private static var scriptURL: URL { directory.appendingPathComponent("block-guard.sh") }
    private static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    /// The job that reopens Alcove while `flag` exists.
    static func plist(script: String, flag: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key>
          <string>\(label)</string>
          <key>ProgramArguments</key>
          <array>
            <string>/bin/bash</string>
            <string>\(xml(script))</string>
          </array>
          <key>RunAtLoad</key>
          <true/>
          <key>KeepAlive</key>
          <dict>
            <key>PathState</key>
            <dict>
              <key>\(xml(flag))</key>
              <true/>
            </dict>
          </dict>
          <key>ThrottleInterval</key>
          <integer>2</integer>
        </dict>
        </plist>
        """
    }

    /// Starts watching. A block that is already being watched is left as it is.
    static func arm(appURL: URL = Bundle.main.bundleURL) {
        guard enabled else { return }
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let script = """
        #!/bin/bash
        flag=\(shell(flagURL.path))
        app=$(cat \(shell(appPathURL.path)))
        while [ -f "$flag" ]; do
          if ! pgrep -x Alcove >/dev/null 2>&1; then
            open "$app"
          fi
          sleep 2
        done
        """
        try? script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        try? appURL.path.write(to: appPathURL, atomically: true, encoding: .utf8)
        try? Data().write(to: flagURL)
        try? plist(script: scriptURL.path, flag: flagURL.path).write(to: plistURL, atomically: true, encoding: .utf8)
        let domain = "gui/\(getuid())"
        run("/bin/launchctl", ["bootout", "\(domain)/\(label)"])
        run("/bin/launchctl", ["bootstrap", domain, plistURL.path])
    }

    /// Stops watching. A normal end of the block calls this, so quitting afterward stays quit.
    static func disarm() {
        guard enabled else { return }
        let domain = "gui/\(getuid())"
        run("/bin/launchctl", ["bootout", "\(domain)/\(label)"])
        try? FileManager.default.removeItem(at: flagURL)
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
