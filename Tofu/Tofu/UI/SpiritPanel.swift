import Foundation

/// Why an intervention notice is triggered. The engine reports these; the mini timer or chat panel decides how it looks.
enum SpiritNotice: Equatable {
    case tabClosed(String)
    case appHidden(String)
    case question(host: String, title: String)
}

/// Short intervention lines displayed in the mini-timer notice or spoken by the assistant.
/// The same host always gets the same line, and different hosts rotate through the pool.
enum SpiritLines {
    static func closedTab(_ host: String) -> String {
        let lines = [
            "I put \(host) away.",
            "\(host) isn't this work. It's closed.",
            "Back to it — \(host) can wait.",
        ]
        return lines[slot(host, count: lines.count)]
    }

    static func appHidden(_ name: String) -> String {
        let lines = [
            "\(name) isn't part of this block.",
            "I set \(name) aside.",
            "Back to the work — \(name) can wait.",
        ]
        return lines[slot(name, count: lines.count)]
    }

    static func question(host: String, title: String) -> String {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty { return "Does \(host) help with this?" }
        return "Does \(host) help? \(title)"
    }

    static func slot(_ seed: String, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let sum = seed.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return sum % count
    }
}
