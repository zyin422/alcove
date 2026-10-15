import Foundation

/// Pure rules behind SubjectEditorView: validation messages and how typed input becomes a Subject.
enum SubjectValidator {
    /// Messages in display order; empty means the subject can be saved.
    /// `sites` are the visible site fields; blank entries do not count as sites.
    static func errors(name: String, sites: [String], preset: LayoutPreset) -> [String] {
        var errors: [String] = []
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Name is required")
        }
        let filled = sites.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if filled.count != preset.siteCount {
            errors.append("Add \(preset.siteCount) site\(preset.siteCount == 1 ? "" : "s") for this layout")
        }
        for (index, site) in sites.enumerated()
        where !site.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && DomainMatcher.normalizedURL(site) == nil {
            errors.append("Site \(index + 1) is not a valid URL")
        }
        return errors
    }

    /// The first `preset.siteCount` entries as full URLs ("cs128.org" -> "https://cs128.org").
    /// Blank or unparseable entries are dropped.
    static func sitesForSave(_ sites: [String], preset: LayoutPreset) -> [String] {
        sites.prefix(preset.siteCount).compactMap { DomainMatcher.normalizedURL($0)?.absoluteString }
    }

    /// Editor slots: always at least 2, so switching to a 1-site layout and back keeps the second site.
    static func siteSlots(_ sites: [String]) -> [String] {
        sites.count >= 2 ? sites : sites + Array(repeating: "", count: 2 - sites.count)
    }

    // MARK: Setup windows

    /// A setup opens at most this many windows; a capture keeps the frontmost ones.
    static let maxWindows = 4

    // MARK: Description

    /// A subject's description is capped at this many words.
    static let maxDetailsWords = 300

    /// Whitespace-separated words in `text`.
    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    /// `text` cut just before its `(limit + 1)`th word; unchanged when it has `limit` words or fewer.
    static func limitingWords(_ text: String, to limit: Int = maxDetailsWords) -> String {
        var count = 0
        var inWord = false
        for index in text.indices {
            let isSpace = text[index].isWhitespace
            if !isSpace && !inWord {
                count += 1
                if count > limit { return String(text[..<index]) }
            }
            inWord = !isSpace
        }
        return text
    }

    /// Messages in display order for a setup made of window slots; empty means it can be saved.
    /// `slots` are the visible ones (one per zone, or the captured windows of a custom layout).
    static func errors(name: String, slots: [SetupSlot], customLayout: Bool) -> [String] {
        var errors: [String] = []
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Name is required")
        }
        if customLayout && slots.isEmpty {
            errors.append("Capture your windows, or pick a layout")
        }
        if slots.count > maxWindows {
            errors.append("Use at most \(maxWindows) windows")
        }
        for (index, slot) in slots.enumerated() {
            let label = "Window \(index + 1)"
            switch slot.kind {
            case .website:
                let urls = slot.urls.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                if urls.first(where: { !$0.isEmpty }) == nil {
                    errors.append("\(label) needs a website")
                } else if urls.contains(where: { !$0.isEmpty && DomainMatcher.normalizedURL($0) == nil }) {
                    errors.append("\(label) has a website that is not a valid URL")
                }
            case .app:
                if slot.app == nil { errors.append("\(label) needs an app") }
            }
        }
        return errors
    }

    /// Slots as saved: website URLs normalized ("cs128.org" -> "https://cs128.org") with blanks dropped,
    /// app slots without a website list, blank folders removed.
    static func slotsForSave(_ slots: [SetupSlot]) -> [SetupSlot] {
        slots.map { slot in
            var saved = slot
            switch slot.kind {
            case .website:
                saved.urls = slot.urls.compactMap { DomainMatcher.normalizedURL($0)?.absoluteString }
                saved.app = nil
                saved.folder = nil
            case .app:
                saved.urls = []
                let folder = (slot.folder ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                saved.folder = folder.isEmpty ? nil : folder
            }
            return saved
        }
    }

    /// Every website of the slots, in order, without duplicates (the setup's study sites).
    static func sites(of slots: [SetupSlot]) -> [String] {
        var seen = Set<String>()
        return slots.filter { $0.kind == .website }.flatMap(\.urls).filter { seen.insert($0).inserted }
    }

    /// Editor zone slots: at least 2, so switching to a 1-zone layout and back keeps the second window.
    static func zoneSlots(_ slots: [SetupSlot]) -> [SetupSlot] {
        slots.count >= 2 ? slots : slots + (slots.count..<2).map { _ in SetupSlot.website([""]) }
    }

    /// "Piazza.com, https://www.stackoverflow.com/questions  docs.python.org" -> normalized hosts,
    /// split on commas and whitespace, deduplicated in order, unparseable entries dropped.
    static func parseDomains(_ text: String) -> [String] {
        let separators = CharacterSet(charactersIn: ",").union(.whitespacesAndNewlines)
        var seen = Set<String>()
        var result: [String] = []
        for token in text.components(separatedBy: separators) where !token.isEmpty {
            guard let host = DomainMatcher.host(of: token), seen.insert(host).inserted else { continue }
            result.append(host)
        }
        return result
    }
}
