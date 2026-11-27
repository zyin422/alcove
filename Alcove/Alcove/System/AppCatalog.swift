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
