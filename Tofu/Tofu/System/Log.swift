import os

/// Unified-logging channels, one per subsystem. View them with
/// `log stream --level debug --predicate 'subsystem == "com.tofu.app"'` or in Console.app.
/// Dynamic strings are private (redacted) by default; only bundle ids, counts and error text are marked public.
enum Log {
    static let subsystem = "com.tofu.app"

    /// Lock-in lifecycle: start, break, end.
    static let session = Logger(subsystem: subsystem, category: "Session")
    /// Apps hidden, quit or blocked during a lock-in.
    static let blocker = Logger(subsystem: subsystem, category: "Blocker")
    /// Chrome / Arc scripting: window setup, tab polling, tab closes.
    static let browser = Logger(subsystem: subsystem, category: "Browser")
    /// AI tab relevance verdicts.
    static let relevance = Logger(subsystem: subsystem, category: "Relevance")
    static let discord = Logger(subsystem: subsystem, category: "Discord")
    static let google = Logger(subsystem: subsystem, category: "Google")
    /// store.json and closed-browser-tabs.json.
    static let storage = Logger(subsystem: subsystem, category: "Storage")
    /// Chat assistant, Mirror and other OpenAI chat calls.
    static let assistant = Logger(subsystem: subsystem, category: "Assistant")
}
