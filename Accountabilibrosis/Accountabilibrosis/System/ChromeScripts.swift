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
