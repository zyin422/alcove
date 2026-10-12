import Foundation

/// Result of `Store.load()`: the data to use, plus a user-facing warning when the file was unreadable.
struct StoreLoadResult {
    var data: StoreData
    var warning: String?
}

/// Reads and writes `StoreData` as one pretty-printed JSON file.
final class Store {
    let fileURL: URL

    init(fileURL: URL) { self.fileURL = fileURL }

    /// ~/Library/Application Support/Tofu/store.json (creates directory).
    static func defaultURL() -> URL {
        let fileManager = FileManager.default
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)
        let directory = base.appendingPathComponent("Tofu", isDirectory: true)
        let file = directory.appendingPathComponent("store.json", isDirectory: false)
        let previous = base.appendingPathComponent("Tofu", isDirectory: true)
            .deletingLastPathComponent()
            .appendingPathComponent(["Acc", "ountabili", "brosis"].joined(), isDirectory: true)
            .appendingPathComponent("store.json", isDirectory: false)
        if !fileManager.fileExists(atPath: file.path), fileManager.fileExists(atPath: previous.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try? fileManager.copyItem(at: previous, to: file)
        }
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return file
    }

    /// Missing file -> .empty, no warning. Corrupt -> rename to store.corrupt-<unix>.json, .empty, warning.
    /// Always applies finalizeInterrupted.
    func load() -> StoreLoadResult {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return StoreLoadResult(data: .empty, warning: nil)
        }
        do {
            let raw = try Data(contentsOf: fileURL)
            let decoded = try Self.makeDecoder().decode(StoreData.self, from: raw)
            return StoreLoadResult(data: Self.finalizeInterrupted(decoded), warning: nil)
        } catch {
            return StoreLoadResult(data: .empty, warning: backUpUnreadableFile())
        }
    }

    /// Atomic write, pretty-printed, ISO8601 dates.
    func save(_ data: StoreData) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoded = try Self.makeEncoder().encode(data)
        try encoded.write(to: fileURL, options: .atomic)
    }

    /// Sessions with end == nil get end = lastHeartbeat, outcome = .interrupted.
    static func finalizeInterrupted(_ data: StoreData) -> StoreData {
        var result = data
        for index in result.sessions.indices where result.sessions[index].end == nil {
            result.sessions[index].end = result.sessions[index].lastHeartbeat
            result.sessions[index].outcome = .interrupted
        }
        return result
    }

    // MARK: - Private

    /// Moves the unreadable file aside (never overwriting an earlier backup) and returns the warning text.
    private func backUpUnreadableFile() -> String {
        let fileManager = FileManager.default
        let directory = fileURL.deletingLastPathComponent()
        let baseName = fileURL.deletingPathExtension().lastPathComponent
        let stamp = Int(Date().timeIntervalSince1970)
        var backupURL = directory.appendingPathComponent("\(baseName).corrupt-\(stamp).json")
        var suffix = 2
        while fileManager.fileExists(atPath: backupURL.path) {
            backupURL = directory.appendingPathComponent("\(baseName).corrupt-\(stamp)-\(suffix).json")
            suffix += 1
        }
        do {
            try fileManager.moveItem(at: fileURL, to: backupURL)
            return "Saved data couldn't be read. It was backed up as \(backupURL.lastPathComponent) and the app started fresh."
        } catch {
            return "Saved data couldn't be read and couldn't be backed up. The app started fresh."
        }
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
