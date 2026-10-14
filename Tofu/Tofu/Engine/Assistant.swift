import Foundation

/// One line in the chat screen.
struct ChatMessage: Identifiable, Equatable {
    enum Role: Equatable {
        /// The bot.
        case assistant
        /// The person (typed or dictated).
        case user
        /// A small centered status line, e.g. "Allowed youtube.com" or "Closed reddit.com".
        case notice
    }
    let id: UUID
    let role: Role
    var text: String
    let date: Date

    init(id: UUID = UUID(), role: Role, text: String, date: Date = Date()) {
        self.id = id
        self.role = role
        self.text = text
        self.date = date
    }
}

/// A site the tab watch could not settle on its own (relevance between 0.4 and 0.7).
struct SiteQuestion: Equatable {
    let host: String
    let url: String
    let title: String
    /// 0...1, higher = more likely related to the subject.
    let relevance: Double
}

/// The tab watch hands unsure sites to the chat assistant through this. Called at most once per host per session.
/// The assistant answers later through `SiteVerdictReceiving`.
@MainActor protocol SiteAsking: AnyObject {
    func askAboutSite(_ question: SiteQuestion, subject: String)
}

/// What the chat assistant may do to other apps during a lock-in (implemented by SessionEngine).
@MainActor protocol AppUnblocking: AnyObject {
    /// Unblocks the app for this work block. The returned text goes back to the model.
    func allowApp(named name: String) -> String
    /// "Name — bundleID" lines for apps quit or blocked this session and not yet allowed.
    var blockedAppsSummary: [String] { get }
}

/// What the chat assistant may do to Chrome (implemented by ChromeController).
@MainActor protocol SiteVerdictReceiving: AnyObject {
    /// Keep every tab on `host` for the rest of the session; it is never checked or closed again.
    func allowHost(_ host: String)
    /// Close every open tab on `host` now and whenever it is opened again this session.
    func closeHost(_ host: String)
    /// Open tabs for the assistant's context, one "host — title" line each (study and Chrome-internal tabs included).
    var openTabsSummary: [String] { get }
}
