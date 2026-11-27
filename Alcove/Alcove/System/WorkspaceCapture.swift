import AppKit

/// What "Capture current windows" found: the windows as setup slots (back to front, so the front window opens
/// last and ends up on top) and the browser of the frontmost browser window, if any.
struct CapturedSetup: Equatable {
    var slots: [SetupSlot]
    var browser: Browser?
}

/// A browser window as the capture script reports it: where it is (Chrome only) and its websites,
/// the active tab first.
struct BrowserWindowCapture: Equatable {
    var bounds: ChromeBounds?
    var urls: [String]
}

/// Copies the current screen into a custom layout: every normal window on the main screen becomes a slot with
/// its position. Browser windows keep their open websites; other apps keep the project folder of the file they
/// show (when the app reports one through Accessibility).
@MainActor enum WorkspaceCapture {
    static let maxWindows = SubjectValidator.maxWindows
    nonisolated static let maxTabsPerWindow = 8
    /// Folders containing one of these are taken as a project root.
    nonisolated static let projectMarkers = [".git", ".vscode", ".idea", "package.json", "Package.swift", "pyproject.toml",
                                             "Cargo.toml", "go.mod", "Makefile"]

    static func capture() -> CapturedSetup {
        guard let screen = NSScreen.main ?? NSScreen.screens.first, let primary = NSScreen.screens.first else {
            return CapturedSetup(slots: [], browser: nil)
        }
        let primaryHeight = primary.frame.height
        let visible = screen.visibleFrame
        let screenRect = CGRect(x: screen.frame.minX, y: primaryHeight - screen.frame.maxY,
                                width: screen.frame.width, height: screen.frame.height)
        let windows = onScreenWindows(in: screenRect)

        let chromeWindows = ChromeController.isRunning(.chrome) ? browserWindows(.chrome) : []
        let arcWindows = ChromeController.isRunning(.arc) ? browserWindows(.arc) : []
        var arcIndex = 0
        var browser: Browser?
        var slots: [SetupSlot] = []
        for window in windows {
            let frame = ScreenGeometry.unitRect(for: window.frame, visible: visible, primaryHeight: primaryHeight)
            switch window.bundleID {
            case Browser.chrome.bundleID:
                browser = browser ?? .chrome
                let match = chromeWindows.first { $0.bounds.map { Self.isClose($0.rect, window.frame) } ?? false }
                slots.append(.website(match?.urls ?? [], frame: frame))
            case Browser.arc.bundleID:
                browser = browser ?? .arc
                let match = arcIndex < arcWindows.count ? arcWindows[arcIndex] : nil
                arcIndex += 1
                slots.append(.website(match?.urls ?? [], frame: frame))
            default:
                let app = AllowedApp(bundleID: window.bundleID, name: window.name)
                slots.append(.app(app, folder: folder(of: window), frame: frame))
            }
        }
        return CapturedSetup(slots: slots.reversed(), browser: browser)
    }

    private struct ScreenWindow {
        let pid: pid_t
        let bundleID: String
        let name: String
        let frame: CGRect
    }

    /// Normal app windows whose center is on `screenRect`, front to back. Skips our own app, Finder,
    /// background apps and tiny windows (palettes, popovers).
    private static func onScreenWindows(in screenRect: CGRect) -> [ScreenWindow] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        var result: [ScreenWindow] = []
        for entry in list {
            guard (entry[kCGWindowLayer as String] as? Int) == 0,
                  let pid = entry[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                  let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: boundsDict),
                  frame.width >= 160, frame.height >= 120,
                  screenRect.contains(CGPoint(x: frame.midX, y: frame.midY)),
                  let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular,
                  let bundleID = app.bundleIdentifier, bundleID != "com.apple.finder" else { continue }
            result.append(ScreenWindow(pid: pid, bundleID: bundleID, name: app.localizedName ?? bundleID, frame: frame))
            if result.count == maxWindows { break }
        }
        return result
    }

    private static func browserWindows(_ browser: Browser) -> [BrowserWindowCapture] {
        guard case .success(let output) = ChromeController.run(captureScript(for: browser)) else { return [] }
        return parseCapture(output)
    }

    /// The project folder for an app window: the folder (or project root of the file) it shows, as "~/…".
    private static func folder(of window: ScreenWindow) -> String? {
        guard WindowPlacer.isTrusted,
              let element = WindowPlacer.windows(of: window.pid).first(where: {
                  WindowPlacer.frame(of: $0).map { isClose($0, window.frame) } ?? false
              }),
              let document = WindowPlacer.document(of: element), document.isFileURL else { return nil }
        let fileManager = FileManager.default
        let folder = projectFolder(for: document, home: fileManager.homeDirectoryForCurrentUser.path,
                                   isDirectory: { path in
                                       var isDirectory: ObjCBool = false
                                       return fileManager.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
                                   },
                                   exists: { fileManager.fileExists(atPath: $0) })
        return (folder as NSString).abbreviatingWithTildeInPath
    }

    // MARK: Pure helpers (unit-tested)

    /// Frames within a few points of each other (window shadows and rounding differ between APIs).
    nonisolated static func isClose(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 6) -> Bool {
        abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance
            && abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }

    /// A folder document is itself the project. For a file, the nearest enclosing folder (up to 8 levels, never
    /// the home folder or "/") containing a project marker; otherwise the file's own folder.
    nonisolated static func projectFolder(for document: URL, home: String, isDirectory: (String) -> Bool,
                                          exists: (String) -> Bool) -> String {
        if isDirectory(document.path) { return document.path }
        let start = document.deletingLastPathComponent()
        var folder = start
        for _ in 0..<8 {
            let path = folder.path
            if path == home || path == "/" || path.isEmpty { break }
            if projectMarkers.contains(where: { exists(folder.appendingPathComponent($0).path) }) { return path }
            folder = folder.deletingLastPathComponent()
        }
        return start.path
    }

    /// Lists every non-minimized window as "left<US>top<US>right<US>bottom<US>activeIndex<US>url<RS>url<RS>…".
    /// Arc has no bounds, so its first four fields are empty; its active tab's URL comes first. Pinned and
    /// favorite tabs are skipped. Spaces Arc is hiding are focused once, then the space that was showing is restored.
    nonisolated static func captureScript(for browser: Browser) -> String {
        let windowPart: String
        switch browser {
        case .chrome:
            windowPart = """
                    if minimized of w is false then
                        set b to bounds of w
                        set urlText to ""
                        repeat with t in tabs of w
                            set urlText to urlText & ((URL of t) as text) & urlSep
                        end repeat
                        set out to out & ((item 1 of b) as text) & sepChar & ((item 2 of b) as text) & sepChar & ((item 3 of b) as text) & sepChar & ((item 4 of b) as text) & sepChar & ((active tab index of w) as text) & sepChar & urlText & lineChar
                    end if
            """
        case .arc:
            return """
                set sepChar to ASCII character 31
                set urlSep to ASCII character 30
                set lineChar to linefeed
                set out to ""
                tell application "Arc"
                    set savedSpace to ""
                    try
                        set savedSpace to (id of active space of front window) as text
                    end try
                    set seenSpaces to {}
                    repeat with w in windows
                        try
                            if minimized of w is false then
                                set urlText to ""
                                try
                                    set urlText to ((URL of active tab of w) as text) & urlSep
                                end try
                                repeat with t in tabs of w
                                    try
                                        set includeTab to true
                                        try
                                            set loc to ((location of t) as text)
                                            if loc is "pinned" or loc is "topApp" then set includeTab to false
                                        end try
                                        if includeTab is true then set urlText to urlText & ((URL of t) as text) & urlSep
                                    end try
                                end repeat
                                repeat with s in spaces of w
                                    try
                                        set sid to (id of s) as text
                                        set seen to false
                                        repeat with previous in seenSpaces
                                            if (previous as text) is sid then set seen to true
                                        end repeat
                                        if seen is false then
                                            set end of seenSpaces to sid
                                            set n to 0
                                            try
                                                set n to count of tabs of s
                                            end try
                                            if n is 0 and sid is not savedSpace then
                                                try
                                                    focus s
                                                    set n to count of tabs of s
                                                end try
                                            end if
                                            if n > 0 then
                                                repeat with t in tabs of s
                                                    try
                                                        set includeTab to true
                                                        try
                                                            set loc to ((location of t) as text)
                                                            if loc is "pinned" or loc is "topApp" then set includeTab to false
                                                        end try
                                                        if includeTab is true then set urlText to urlText & ((URL of t) as text) & urlSep
                                                    end try
                                                end repeat
                                            end if
                                        end if
                                    end try
                                end repeat
                                set out to out & sepChar & sepChar & sepChar & sepChar & "1" & sepChar & urlText & lineChar
                            end if
                        end try
                    end repeat
                    if savedSpace is not "" then
                        try
                            tell front window
                                focus space id savedSpace
                            end tell
                        end try
                    end if
                end tell
                return out
                """
        }
        return """
            set sepChar to ASCII character 31
            set urlSep to ASCII character 30
            set lineChar to linefeed
            set out to ""
            tell application "\(browser.scriptName)"
                repeat with w in windows
            \(windowPart)
                end repeat
            end tell
            return out
            """
    }

    /// Parses `captureScript` output. Only http(s) URLs are kept (no new-tab pages), without duplicates,
    /// the active tab first, at most `maxTabsPerWindow`.
    nonisolated static func parseCapture(_ output: String) -> [BrowserWindowCapture] {
        output.split(whereSeparator: { $0 == "\n" || $0 == "\r" }).compactMap { line in
            let fields = line.split(separator: "\u{1F}", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 6 else { return nil }
            let numbers = fields[0..<4].compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            let bounds = numbers.count == 4
                ? ChromeBounds(left: numbers[0], top: numbers[1], right: numbers[2], bottom: numbers[3]) : nil
            var urls = fields[5...].joined(separator: "\u{1F}")
                .split(separator: "\u{1E}").map { $0.trimmingCharacters(in: .whitespaces) }
            if let active = Int(fields[4]), active >= 1, active <= urls.count, active > 1 {
                urls.insert(urls.remove(at: active - 1), at: 0)
            }
            var seen = Set<String>()
            let kept = urls.filter { url in
                (url.hasPrefix("https://") || url.hasPrefix("http://")) && seen.insert(url).inserted
            }
            return BrowserWindowCapture(bounds: bounds, urls: Array(kept.prefix(maxTabsPerWindow)))
        }
    }
}
