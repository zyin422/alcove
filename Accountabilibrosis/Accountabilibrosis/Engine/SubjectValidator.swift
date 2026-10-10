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
