import Foundation

/// Title, description and site name of a web page, scraped from its HTML head.
enum PageMetadata {
    typealias Fields = (title: String?, description: String?, siteName: String?)

    /// Only this many leading characters of the HTML are scanned.
    static let maxScannedCharacters = 200_000
    /// Bytes of a response body that are decoded (the head is always near the start).
    private static let maxBodyBytes = 1_000_000
    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    private static let empty: Fields = (nil, nil, nil)

    // MARK: - Fetch

    /// GETs the page and parses it. Any failure (bad scheme, network error, non-2xx, timeout) gives all nils.
    static func fetch(url: String, transport: HTTPTransport = URLSessionTransport(),
                      timeout: TimeInterval = 2) async -> Fields {
        guard let target = URL(string: url.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = target.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = target.host(percentEncoded: false), !host.isEmpty else { return empty }
        var request = URLRequest(url: target, timeoutInterval: timeout)
        request.httpMethod = "GET"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml;q=0.9,*/*;q=0.5", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await transport.send(request)
            guard (200..<300).contains(response.statusCode), let html = decode(data) else { return empty }
            return parse(html: html)
        } catch {
            return empty
        }
    }

    /// UTF-8, else ISO Latin-1. A body cut at `maxBodyBytes` may end mid-character, so a few trailing bytes may be dropped.
    private static func decode(_ data: Data) -> String? {
        let truncated = data.count > maxBodyBytes
        let slice = truncated ? data.prefix(maxBodyBytes) : data
        for trim in 0...(truncated ? 3 : 0) {
            if let text = String(data: slice.dropLast(trim), encoding: .utf8) { return text }
        }
        return String(data: slice, encoding: .isoLatin1)
    }

    // MARK: - Parse

    /// `<title>` (else og:title), `<meta name="description">` (else og:description), og:site_name.
    /// Empty values are nil; entities are decoded; whitespace is collapsed.
    static func parse(html: String) -> Fields {
        let head = String(html.prefix(maxScannedCharacters))
        var metas: [String: String] = [:]   // lowercased name/property -> first non-empty content
        for tag in matches(metaTagPattern, in: head) {
            let attributes = attributes(of: tag)
            guard let content = attributes["content"].map(normalize), !content.isEmpty else { continue }
            for key in [attributes["name"], attributes["property"]].compactMap({ $0?.lowercased() }) {
                if metas[key] == nil { metas[key] = content }
            }
        }
        let title = firstGroup(titlePattern, in: head).map(normalize).flatMap { $0.isEmpty ? nil : $0 }
        return (title: title ?? metas["og:title"],
                description: metas["description"] ?? metas["og:description"],
                siteName: metas["og:site_name"])
    }

    // MARK: - Private

    private static let titlePattern = regex(#"<title\b[^>]*>(.*?)</title\s*>"#)
    /// A `<meta ...>` tag; a `>` inside a quoted attribute value does not end it.
    private static let metaTagPattern = regex(#"<meta\b(?:[^>"']|"[^"]*"|'[^']*')*>"#)
    private static let attributePattern =
        regex(#"([A-Za-z_:][-A-Za-z0-9_:.]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))"#)
    private static let entityPattern = regex(#"&(#[xX][0-9A-Fa-f]+|#[0-9]+|[A-Za-z]+);"#, caseInsensitive: false)

    private static func regex(_ pattern: String, caseInsensitive: Bool = true) -> NSRegularExpression {
        var options: NSRegularExpression.Options = [.dotMatchesLineSeparators]
        if caseInsensitive { options.insert(.caseInsensitive) }
        // The patterns are literals in this file; a failure here is a programming error caught by the tests.
        return try! NSRegularExpression(pattern: pattern, options: options)
    }

    private static func matches(_ expression: NSRegularExpression, in text: String) -> [String] {
        let range = NSRange(text.startIndex..., in: text)
        return expression.matches(in: text, range: range).compactMap { Range($0.range, in: text).map { String(text[$0]) } }
    }

    private static func firstGroup(_ expression: NSRegularExpression, in text: String) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = expression.firstMatch(in: text, range: range), match.numberOfRanges > 1,
              let group = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[group])
    }

    /// lowercased attribute name -> raw value, first occurrence wins.
    private static func attributes(of tag: String) -> [String: String] {
        var result: [String: String] = [:]
        let range = NSRange(tag.startIndex..., in: tag)
        for match in attributePattern.matches(in: tag, range: range) {
            guard let nameRange = Range(match.range(at: 1), in: tag) else { continue }
            let name = tag[nameRange].lowercased()
            let value = (2...4).lazy
                .compactMap { Range(match.range(at: $0), in: tag) }
                .first
                .map { String(tag[$0]) }
            if result[name] == nil, let value { result[name] = value }
        }
        return result
    }

    private static func normalize(_ raw: String) -> String {
        decodeEntities(raw).components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static let namedEntities = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " "]

    /// One pass, so `&amp;lt;` becomes `&lt;` and not `<`. Unknown entities are left as written.
    private static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        let result = NSMutableString(string: text)
        let matches = entityPattern.matches(in: text, range: NSRange(location: 0, length: result.length))
        for match in matches.reversed() {
            let body = result.substring(with: match.range(at: 1))
            var replacement: String?
            if body.hasPrefix("#") {
                let digits = body.dropFirst()
                let scalar = digits.first == "x" || digits.first == "X"
                    ? UInt32(digits.dropFirst(), radix: 16) : UInt32(digits, radix: 10)
                replacement = scalar.flatMap(Unicode.Scalar.init).map { String(Character($0)) }
            } else {
                replacement = namedEntities[body.lowercased()]
            }
            if let replacement { result.replaceCharacters(in: match.range, with: replacement) }
        }
        return result as String
    }
}
