import Foundation

/// Reads the repo-root `.env` file that the build copies into the app bundle as `discord.env`.
/// This is how the team's shared Discord bot token reaches the app without anyone pasting it.
enum EnvFile {
    /// Name of the bundled copy of `.env` (see the post-compile script in project.yml).
    static let bundledName = "discord"
    static let bundledExtension = "env"

    /// Parses `KEY=VALUE` lines.
    /// - Blank lines and lines starting with `#` are ignored; so are lines without a key or an `=`.
    /// - Whitespace around the key and the value is trimmed; an optional `export ` prefix is allowed.
    /// - The first `=` splits key from value. One pair of matching single or double quotes around the value is removed.
    /// - When a key appears twice, the later line wins.
    static func parse(_ text: String) -> [String: String] {
        var values: [String: String] = [:]
        let body = text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
        for rawLine in body.split(whereSeparator: \.isNewline) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            if line.hasPrefix("export ") {
                line = String(line.dropFirst("export ".count)).trimmingCharacters(in: .whitespaces)
            }
            guard let equals = line.firstIndex(of: "=") else { continue }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            values[key] = unquoted(value)
        }
        return values
    }

    /// The value for `key` from the bundled `discord.env`, or nil when the file is missing or the value is blank.
    static func bundledValue(_ key: String, bundle: Bundle = .main) -> String? {
        guard let url = bundle.url(forResource: bundledName, withExtension: bundledExtension),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let value = (parse(text)[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    /// Drops one pair of matching surrounding quotes.
    private static func unquoted(_ value: String) -> String {
        guard value.count >= 2, let first = value.first, first == value.last,
              first == "\"" || first == "'" else { return value }
        return String(value.dropFirst().dropLast())
    }
}
