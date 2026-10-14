import Foundation

/// A window or tab id as a script reports it. Chrome's are numbers; Arc's are text. Integer and string
/// literals both work, and `description` is the raw text put back into scripts.
struct ScriptID: Hashable, Comparable, CustomStringConvertible, ExpressibleByIntegerLiteral, ExpressibleByStringLiteral {
    let raw: String

    init(_ raw: String) { self.raw = raw }
    init(_ value: Int) { raw = String(value) }
    init(integerLiteral value: Int) { raw = String(value) }
    init(stringLiteral value: String) { raw = value }

    var description: String { raw }

    /// Numbers in numeric order, otherwise text order.
    static func < (lhs: ScriptID, rhs: ScriptID) -> Bool {
        if let left = Int(lhs.raw), let right = Int(rhs.raw) { return left < right }
        return lhs.raw < rhs.raw
    }
}

/// One browser tab as reported by `ChromeScripts.listTabs`.
struct ChromeTab: Equatable {
    let windowID: ScriptID
    let tabIndex: Int   // 1-based AppleScript index
    /// The browser's own id for the tab. Unlike `tabIndex` it does not shift when other tabs open or close.
    let tabID: ScriptID
    let title: String
    let url: String
}

enum ChromeError: Error, Equatable {
    case notInstalled
    case automationDenied
    case profileNotReady
    case scriptFailed(String)
}

/// AppleScript source for the setup browsers (Google Chrome, Arc) plus parsers for the scripts' text output.
/// Pure: nothing here runs a script. Window ids are text in both browsers, so they are quoted when put back
/// into a script; Chrome's tab ids are integers, Arc's are text.
enum ChromeScripts {
    static let bundleID = Browser.chrome.bundleID

    /// Escapes backslash and double quote for embedding in an AppleScript string literal.
    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func tell(_ browser: Browser) -> String { "tell application \"\(browser.scriptName)\"" }

    /// Makes a new window, sets active tab URL and bounds; returns the new window id as text.
    static func openWindow(url: String, bounds: ChromeBounds) -> String {
        openWindowScript(urls: [url], bounds: bounds, browser: .chrome)
    }

    /// Same as `openWindow(url:bounds:)` but leaves the window wherever Chrome puts it (no bounds line).
    static func openWindow(url: String) -> String {
        openWindowScript(urls: [url], bounds: nil, browser: .chrome)
    }

    /// A new window showing `urls[0]`, with the other URLs as extra tabs behind it; returns the window id.
    /// Bounds are only set where the browser supports them (Chrome).
    static func openWindow(urls: [String], bounds: ChromeBounds?, browser: Browser) -> String {
        openWindowScript(urls: urls, bounds: bounds, browser: browser)
    }

    private static func openWindowScript(urls: [String], bounds: ChromeBounds?, browser: Browser) -> String {
        if browser == .arc { return arcOpenWindowScript(urls: urls) }
        var lines = [tell(browser), "    set w to make new window"]
        switch browser {
        case .chrome:
            if let first = urls.first {
                lines.append("    set URL of active tab of w to \"\(escape(first))\"")
            }
            for url in urls.dropFirst() {
                lines.append("    make new tab at end of tabs of w with properties {URL:\"\(escape(url))\"}")
            }
            if urls.count > 1 {
                lines.append("    set active tab index of w to 1")
            }
        case .arc:
            break
        }
        if let b = bounds, browser.supportsBounds {
            lines.append("    set bounds of w to {\(b.left), \(b.top), \(b.right), \(b.bottom)}")
        }
        lines.append("    return id of w as text")
        lines.append("end tell")
        return lines.joined(separator: "\n")
    }

    /// Arc's `make new window` returns no window, and a stored window reference can't be told anything, so the
    /// new window is addressed as `front window`. Tabs are made last-to-first: Arc shows the last tab made.
    /// A URL that is already open is not made again (Arc keeps one tab list per space, so a second `make new tab`
    /// would duplicate it). Nothing after the window exists can fail, so a retry can't add another window of tabs.
    private static func arcOpenWindowScript(urls: [String]) -> String {
        var lines = [tell(.arc), "    make new window", "    delay 0.3", "    try", "        tell front window"]
        for url in urls.reversed() {
            let quoted = "\"\(escape(url))\""
            lines += ["            set already to false",
                      "            repeat with t in tabs",
                      "                try",
                      "                    if ((URL of t) as text) is \(quoted) then set already to true",
                      "                end try",
                      "            end repeat",
                      "            repeat with s in spaces",
                      "                repeat with t in tabs of s",
                      "                    try",
                      "                        if ((URL of t) as text) is \(quoted) then set already to true",
                      "                    end try",
                      "                end repeat",
                      "            end repeat",
                      "            if already is false then make new tab with properties {URL:\(quoted)}"]
        }
        lines += ["        end tell", "    end try", "    try", "        return (id of front window) as text",
                  "    on error", "        return \"opened\"", "    end try", "end tell"]
        return lines.joined(separator: "\n")
    }

    /// ASCII 31 (unit separator): splits the fields of a `listTabs` line. Unlike a tab it practically never
    /// appears in a page title, and it cannot appear in a URL.
    static let fieldSeparator: Character = "\u{1F}"

    /// Returns lines "windowID<US>tabIndex<US>tabID<US>title<US>url" separated by linefeed, for every tab of every
    /// window (`<US>` is `fieldSeparator`). The URL is last, so it can never be confused with the title.
    /// The separator and `linefeed` are captured before the tell block, because inside it names like `tab` mean
    /// Chrome's own classes.
    static let listTabs: String = listTabs(for: .chrome)

    /// First field of a `listTabs` line that names an Arc space with no tabs. Not a tab: `parseTabs` ignores it.
    /// The next poll passes these ids back as `quietArcSpaces` so an empty space is not focused again.
    static let arcEmptySpaceMarker = "#space"

    /// `listTabs` for `browser`. Arc skips pinned and favorite tabs (they live in the sidebar, and closing one
    /// would delete it). A tab whose location can't be read is still listed: a new tab often won't answer yet.
    /// Arc's window tab list hides every space that has not been focused, so those spaces are focused once and the
    /// space that was showing is focused again afterward. `quietArcSpaces` are spaces already found empty.
    static func listTabs(for browser: Browser, quietArcSpaces: [String] = []) -> String {
        let line = "set out to out & wid & sepChar & (i as text) & sepChar & ((id of t) as text) & sepChar & ((title of t) as text) & sepChar & ((URL of t) as text) & lineChar"
        switch browser {
        case .chrome:
            return """
                set sepChar to ASCII character 31
                set lineChar to linefeed
                set out to ""
                tell application "\(browser.scriptName)"
                    repeat with w in windows
                        set wid to (id of w) as text
                        set tabList to every tab of w
                        repeat with i from 1 to count of tabList
                            set t to item i of tabList
                            \(line)
                        end repeat
                    end repeat
                end tell
                return out
                """
        case .arc:
            // `item i of every tab` makes Arc refuse `location` for the whole script, so nothing would be
            // remembered or closed. Walk the tabs directly, and skip a tab that still won't answer.
            let quiet = appleScriptList(quietArcSpaces)
            let marker = arcEmptySpaceMarker
            return """
                set sepChar to ASCII character 31
                set lineChar to linefeed
                set out to ""
                set quietSpaces to \(quiet)
                tell application "Arc"
                    set savedSpace to ""
                    try
                        set savedSpace to (id of active space of front window) as text
                    end try
                    set seenSpaces to {}
                    repeat with w in windows
                        try
                            set wid to (id of w) as text
                            set i to 0
                            repeat with t in tabs of w
                                set i to i + 1
                                try
                                    set includeTab to true
                                    try
                                        set loc to ((location of t) as text)
                                        if loc is "pinned" or loc is "topApp" then set includeTab to false
                                    end try
                                    if includeTab is true then
                                        \(line)
                                    end if
                                end try
                            end repeat
                        end try
                    end repeat
                    repeat with w in windows
                        try
                            set wid to (id of w) as text
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
                                        set shouldFocus to false
                                        if n is 0 and sid is not savedSpace then
                                            set shouldFocus to true
                                            repeat with q in quietSpaces
                                                if (q as text) is sid then set shouldFocus to false
                                            end repeat
                                        end if
                                        if shouldFocus is true then
                                            try
                                                focus s
                                                set n to count of tabs of s
                                            end try
                                        end if
                                        if n is 0 then
                                            set out to out & "\(marker)" & sepChar & sid & lineChar
                                        else
                                            set i to 0
                                            repeat with t in tabs of s
                                                set i to i + 1
                                                try
                                                    set includeTab to true
                                                    try
                                                        set loc to ((location of t) as text)
                                                        if loc is "pinned" or loc is "topApp" then set includeTab to false
                                                    end try
                                                    if includeTab is true then
                                                        \(line)
                                                    end if
                                                end try
                                            end repeat
                                        end if
                                    end if
                                end try
                            end repeat
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
    }

    /// An AppleScript list literal of escaped strings. `{}` when there is nothing to skip.
    private static func appleScriptList(_ values: [String]) -> String {
        "{" + values.map { "\"\(escape($0))\"" }.joined(separator: ", ") + "}"
    }

    /// Closes the tab with the browser's id `tabID` in the window. Addressing by id (not index) means a tab whose
    /// index shifted, or that has already gone, is never closed by mistake: the script then matches nothing.
    static func closeTab(windowID: ScriptID, tabID: ScriptID, browser: Browser = .chrome) -> String {
        let id = browser.hasTextTabIDs ? "\"\(escape(tabID.raw))\"" : tabID.raw
        let windowClose = "close (every tab of window id \"\(escape(windowID.raw))\" whose id is \(id))"
        guard browser == .arc else { return "\(tell(browser)) to \(windowClose)" }
        // A tab Arc has not yet put on the window (it still lives only on its space) is missed by the window close.
        return """
            tell application "Arc"
                try
                    \(windowClose)
                end try
                repeat with w in windows
                    try
                        repeat with s in spaces of w
                            try
                                close (every tab of s whose id is \(id))
                            end try
                        end repeat
                    end try
                end repeat
            end tell
            """
    }

    /// Closes every window of the browser. Arc can only close its front window by script, and its window count
    /// includes windows already closed, so it closes the front window that many times (an extra close does nothing).
    /// Arc keeps a closed window's tabs in its sidebar; only `closeTabs` removes them.
    static func closeAllWindows(for browser: Browser) -> String {
        switch browser {
        case .chrome:
            return "\(tell(.chrome)) to close every window"
        case .arc:
            // Arc's window count counts windows that are already gone, so repeat a fixed number of times.
            // Closing the front window when none is left does nothing.
            return """
                tell application "Arc"
                    repeat 40 times
                        try
                            close front window
                        end try
                    end repeat
                end tell
                """
        }
    }

    /// Closes each of these tabs by id (inside `try`, so one that is already gone does not stop the rest).
    /// "" (nothing to run) for no tabs.
    static func closeTabs(_ tabs: [ChromeTab], browser: Browser) -> String {
        guard !tabs.isEmpty else { return "" }
        var lines = [tell(browser)]
        for tab in tabs {
            let id = browser.hasTextTabIDs ? "\"\(escape(tab.tabID.raw))\"" : tab.tabID.raw
            lines += ["    try",
                      "        close (every tab of window id \"\(escape(tab.windowID.raw))\" whose id is \(id))",
                      "    end try"]
            if browser == .arc {
                lines += ["    repeat with w in windows",
                          "        try",
                          "            repeat with s in spaces of w",
                          "                try",
                          "                    close (every tab of s whose id is \(id))",
                          "                end try",
                          "            end repeat",
                          "        end try",
                          "    end repeat"]
            }
        }
        lines.append("end tell")
        return lines.joined(separator: "\n")
    }

    /// Minimizes all non-minimized windows; returns their ids comma-separated ("" if none).
    static let minimizeAll: String = minimizeAll(for: .chrome)

    static func minimizeAll(for browser: Browser) -> String {
        """
        set idList to {}
        tell application "\(browser.scriptName)"
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
    }

    /// Un-minimizes the given windows; ids that no longer exist are skipped by `try`.
    static func restore(windowIDs: [ScriptID], browser: Browser = .chrome) -> String {
        setMinimized(false, windowIDs: windowIDs, browser: browser)
    }

    /// Minimizes the given windows; ids that no longer exist are skipped by `try`. "" (nothing to run) for no ids.
    static func minimize(windowIDs: [ScriptID], browser: Browser = .chrome) -> String {
        guard !windowIDs.isEmpty else { return "" }
        return setMinimized(true, windowIDs: windowIDs, browser: browser)
    }

    private static func setMinimized(_ minimized: Bool, windowIDs: [ScriptID], browser: Browser) -> String {
        var lines = [tell(browser)]
        for id in windowIDs {
            lines.append("    try")
            lines.append("        set minimized of window id \"\(escape(id.raw))\" to \(minimized)")
            lines.append("    end try")
        }
        lines.append("end tell")
        return lines.joined(separator: "\n")
    }

    /// Harmless call used to trigger/check the Automation permission: returns count of windows.
    static let ping: String = ping(for: .chrome)

    static func ping(for browser: Browser) -> String { "\(tell(browser)) to count windows" }

    /// Space ids Arc reported as empty (`arcEmptySpaceMarker` lines). Tab lines are ignored. Order is stable.
    static func emptyArcSpaceIDs(in output: String) -> [String] {
        var seen = Set<String>()
        let ids = output.split(whereSeparator: { $0 == "\n" || $0 == "\r" }).compactMap { line -> String? in
            let parts = line.split(separator: fieldSeparator, omittingEmptySubsequences: false)
            guard parts.count >= 2, parts[0] == Substring(arcEmptySpaceMarker) else { return nil }
            let id = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, seen.insert(id).inserted else { return nil }
            return id
        }
        return ids.sorted()
    }

    /// Parses `listTabs` output. Lines with fewer than five fields are skipped, and so are Chrome lines whose
    /// ids are not integers (Arc ids are text, so any non-empty id counts there).
    /// The first three fields and the last one (the URL) are fixed; if a title contains the separator itself,
    /// the pieces between them are rejoined with spaces. The URL keeps any spaces.
    /// Every Arc window of a space lists the same tabs, so Arc tabs are kept once (in the first window listing them).
    static func parseTabs(_ output: String, browser: Browser = .chrome) -> [ChromeTab] {
        let tabs = parseTabLines(output, browser: browser)
        guard browser == .arc else { return tabs }
        var seen = Set<ScriptID>()
        return tabs.filter { seen.insert($0.tabID).inserted }
    }

    private static func parseTabLines(_ output: String, browser: Browser) -> [ChromeTab] {
        // Only CR/LF end a line: Unicode line separators (U+2028, U+0085) can occur in page titles.
        output.split(whereSeparator: { $0 == "\n" || $0 == "\r" || $0 == "\r\n" }).compactMap { line in
            let parts = line.split(separator: fieldSeparator, omittingEmptySubsequences: false)
            guard parts.count >= 5,
                  let windowID = id(parts[0], browser: browser),
                  let tabIndex = Int(parts[1].trimmingCharacters(in: .whitespaces)),
                  let tabID = id(parts[2], browser: browser) else { return nil }
            let title = parts[3..<(parts.count - 1)].joined(separator: " ")
            return ChromeTab(windowID: windowID, tabIndex: tabIndex, tabID: tabID, title: title,
                             url: String(parts[parts.count - 1]))
        }
    }

    /// Parses `minimizeAll` / `openWindow` output: comma-separated ids; junk entries are dropped.
    static func parseIDs(_ output: String, browser: Browser = .chrome) -> [ScriptID] {
        output.split(separator: ",").compactMap { id($0, browser: browser) }
    }

    private static func id(_ text: Substring, browser: Browser) -> ScriptID? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch browser {
        case .chrome: return Int(trimmed).map { ScriptID(String($0)) }
        case .arc: return trimmed.isEmpty ? nil : ScriptID(trimmed)
        }
    }

    /// Identity of a tab that already existed before the session. Chrome: "windowID<TAB>url" (index-independent).
    /// Arc shows the same tabs in every window of a space, so its stable text tab id is used instead.
    static func protectionKey(_ tab: ChromeTab) -> String {
        Int(tab.tabID.raw) == nil ? "tab\t\(tab.tabID.raw)" : "\(tab.windowID)\t\(tab.url)"
    }
}
