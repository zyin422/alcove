import Foundation

/// One Chrome tab as reported by `ChromeScripts.listTabs`.
struct ChromeTab: Equatable {
    let windowID: Int
    let tabIndex: Int   // 1-based AppleScript index
    /// Chrome's own id for the tab. Unlike `tabIndex` it does not shift when other tabs open or close.
    let tabID: Int
    let title: String
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

    /// ASCII 31 (unit separator): splits the fields of a `listTabs` line. Unlike a tab it practically never
    /// appears in a page title, and it cannot appear in a URL.
    static let fieldSeparator: Character = "\u{1F}"

    /// Returns lines "windowID<US>tabIndex<US>tabID<US>title<US>url" separated by linefeed, for every tab of every
    /// window (`<US>` is `fieldSeparator`). The URL is last, so it can never be confused with the title.
    /// The separator and `linefeed` are captured before the tell block, because inside it names like `tab` mean
    /// Chrome's own classes.
    static let listTabs: String = """
        set sepChar to ASCII character 31
        set lineChar to linefeed
        set out to ""
        tell application "Google Chrome"
            repeat with w in windows
                set wid to (id of w) as text
                set tabList to every tab of w
                repeat with i from 1 to count of tabList
                    set t to item i of tabList
                    set out to out & wid & sepChar & (i as text) & sepChar & ((id of t) as text) & sepChar & ((title of t) as text) & sepChar & ((URL of t) as text) & lineChar
                end repeat
            end repeat
        end tell
        return out
        """

    /// Closes the tab with Chrome's id `tabID` in the window. Addressing by id (not index) means a tab whose
    /// index shifted, or that has already gone, is never closed by mistake: the script then matches nothing.
    static func closeTab(windowID: Int, tabID: Int) -> String {
        "tell application \"Google Chrome\" to close (every tab of window id \"\(windowID)\" whose id is \(tabID))"
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

    /// Minimizes the given windows; ids that no longer exist are skipped by `try`. "" (nothing to run) for no ids.
    static func minimize(windowIDs: [Int]) -> String {
        guard !windowIDs.isEmpty else { return "" }
        var lines = ["tell application \"Google Chrome\""]
        for id in windowIDs {
            lines.append("    try")
            lines.append("        set minimized of window id \"\(id)\" to true")
            lines.append("    end try")
        }
        lines.append("end tell")
        return lines.joined(separator: "\n")
    }

    /// Harmless call used to trigger/check the Automation permission: returns count of windows.
    static let ping: String = "tell application \"Google Chrome\" to count windows"

    /// Parses `listTabs` output. Lines with fewer than five fields or non-integer ids are skipped.
    /// The first three fields and the last one (the URL) are fixed; if a title contains the separator itself,
    /// the pieces between them are rejoined with spaces. The URL keeps any spaces.
    static func parseTabs(_ output: String) -> [ChromeTab] {
        // Only CR/LF end a line: Unicode line separators (U+2028, U+0085) can occur in page titles.
        output.split(whereSeparator: { $0 == "\n" || $0 == "\r" || $0 == "\r\n" }).compactMap { line in
            let parts = line.split(separator: fieldSeparator, omittingEmptySubsequences: false)
            guard parts.count >= 5,
                  let windowID = Int(parts[0].trimmingCharacters(in: .whitespaces)),
                  let tabIndex = Int(parts[1].trimmingCharacters(in: .whitespaces)),
                  let tabID = Int(parts[2].trimmingCharacters(in: .whitespaces)) else { return nil }
            let title = parts[3..<(parts.count - 1)].joined(separator: " ")
            return ChromeTab(windowID: windowID, tabIndex: tabIndex, tabID: tabID, title: title,
                             url: String(parts[parts.count - 1]))
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
}
