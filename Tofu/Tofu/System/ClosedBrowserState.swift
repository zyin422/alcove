import Foundation

/// What a lock-in closed in the browser, so it can all be opened again when the session ends: the user's own
/// windows (closed at lock-in, one URL list per window) and the off-task tabs closed during the session.
/// Saved to disk on every change, so a crash mid-session loses nothing; reopened on the next launch then.
struct ClosedBrowserState: Codable, Equatable {
    var browser: Browser
    /// The user's windows as they were at lock-in, front to back, each with its tabs in order.
    var windows: [[String]]
    /// Off-task tabs closed during the session, oldest first.
    var closedTabs: [String]

    var isEmpty: Bool { windows.allSatisfy(\.isEmpty) && closedTabs.isEmpty }

    /// Only pages that can be opened again by URL (not "chrome://newtab" and the like).
    static func isReopenable(_ url: String) -> Bool {
        let lower = url.lowercased()
        return lower.hasPrefix("https://") || lower.hasPrefix("http://") || lower.hasPrefix("file://")
    }

    /// The windows to remember from a tab list: Chrome keeps one entry per window (tabs by index, windows in
    /// listing order, i.e. front to back). Every Arc window shows the same tabs, so Arc gets a single window.
    static func windows(from tabs: [ChromeTab], browser: Browser) -> [[String]] {
        var order: [ScriptID] = []
        var byWindow: [ScriptID: [ChromeTab]] = [:]
        for tab in tabs where isReopenable(tab.url) {
            let key: ScriptID = browser == .arc ? "arc" : tab.windowID
            if byWindow[key] == nil { order.append(key) }
            byWindow[key, default: []].append(tab)
        }
        return order.map { key in
            var seen = Set<String>()
            let sorted = browser == .arc ? byWindow[key]! : byWindow[key]!.sorted { $0.tabIndex < $1.tabIndex }
            return sorted.map(\.url).filter { seen.insert($0).inserted }
        }
    }

    /// Adds another lock-in's windows (a state not yet reopened is never overwritten).
    mutating func merge(_ other: ClosedBrowserState) {
        windows += other.windows
        closedTabs += other.closedTabs
    }

    /// The windows to open at the end: the remembered windows, then one window with the closed tabs (Arc puts
    /// everything in one window). Pages already open are skipped, every page opens once, empty windows are dropped.
    /// Reopened back to front, so the front window ends up on top again.
    func windowsToReopen(alreadyOpen: Set<String>) -> [[String]] {
        var seen = alreadyOpen
        func fresh(_ urls: [String]) -> [String] { urls.filter { isReopenableAndNew($0, &seen) } }
        var result: [[String]]
        if browser == .arc {
            result = [fresh(windows.flatMap { $0 } + closedTabs)]
        } else {
            result = windows.reversed().map(fresh)
            result.append(fresh(closedTabs))
        }
        return result.filter { !$0.isEmpty }
    }

    private func isReopenableAndNew(_ url: String, _ seen: inout Set<String>) -> Bool {
        Self.isReopenable(url) && seen.insert(url).inserted
    }

    // MARK: File

    static func defaultURL() -> URL {
        Store.defaultURL().deletingLastPathComponent().appendingPathComponent("closed-browser-tabs.json")
    }

    static func load(from url: URL?) -> ClosedBrowserState? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ClosedBrowserState.self, from: data)
    }

    /// Writes the state, or removes the file for nil / an empty state.
    static func save(_ state: ClosedBrowserState?, to url: URL?) {
        guard let url else { return }
        guard let state, !state.isEmpty, let data = try? JSONEncoder().encode(state) else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        try? data.write(to: url, options: .atomic)
    }
}
