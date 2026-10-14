import Foundation

/// Decides which Chrome tabs belong to the current subject (spec §8).
enum DomainMatcher {
    /// The browser's own pages and blank tabs. Tabs whose URL starts with one of these are never closed.
    private static let internalPrefixes = [
        "chrome://", "chrome-extension://", "chrome-search://", "chrome-untrusted://", "devtools://", "about:",
        "arc://",
    ]

    /// lowercase, trim whitespace, strip leading "www." and trailing ".".
    static func normalize(_ domain: String) -> String {
        var result = domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while result.hasSuffix(".") {
            result.removeLast()
        }
        if result.hasPrefix("www.") {
            result.removeFirst(4)
        }
        return result
    }

    /// Adds "https://" when the string has no scheme. nil if no host results.
    static func normalizedURL(_ string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let candidate = hasScheme(trimmed) ? trimmed : "https://" + trimmed
        guard let url = URL(string: candidate),
              let host = url.host(percentEncoded: false),
              !host.isEmpty else { return nil }
        return url
    }

    /// Normalized host of a URL string, or nil.
    static func host(of urlString: String) -> String? {
        guard let rawHost = normalizedURL(urlString)?.host(percentEncoded: false) else { return nil }
        let host = normalize(rawHost)
        return host.isEmpty ? nil : host
    }

    /// Hosts of sites + extra domains, normalized, deduplicated, order preserved, empties dropped.
    static func allowedDomains(sites: [String], extra: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for entry in sites + extra {
            guard let domain = host(of: entry), seen.insert(domain).inserted else { continue }
            result.append(domain)
        }
        return result
    }

    /// See spec §8. Blank, Chrome-internal and unparseable URLs are allowed; otherwise the
    /// normalized host must equal an allowed domain or end with "." + that domain.
    static func isAllowed(_ urlString: String, allowed: [String]) -> Bool {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        let lowered = trimmed.lowercased()
        if internalPrefixes.contains(where: { lowered.hasPrefix($0) }) { return true }
        guard let rawHost = URL(string: trimmed)?.host(percentEncoded: false) else { return true }
        let host = normalize(rawHost)
        if host.isEmpty { return true }
        return allowed.contains { entry in
            let domain = normalize(entry)
            return !domain.isEmpty && (host == domain || host.hasSuffix("." + domain))
        }
    }

    /// True when the string starts with an RFC 3986 scheme followed by "://", e.g. "https://".
    private static func hasScheme(_ string: String) -> Bool {
        guard let separator = string.range(of: "://") else { return false }
        let scheme = string[string.startIndex..<separator.lowerBound]
        guard let first = scheme.first, first.isASCII, first.isLetter else { return false }
        return scheme.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == ".") }
    }
}
