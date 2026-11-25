import Foundation

/// What the tab watch knows about one Chrome tab when it asks whether the page belongs to the session.
struct PageInfo: Equatable {
    var url: String
    var title: String
    /// `<meta name="description">` or `og:description`, when the page could be fetched.
    var description: String?
    /// `og:site_name`, when present.
    var siteName: String?
}

/// Outcome of one relevance check.
enum RelevanceVerdict: Equatable {
    /// The page supports the subject: keep the tab.
    case relevant
    /// The page is off-task (relevance below `RelevanceJudge.closeBelow`): close the tab.
    case offTask
    /// Relevance between `RelevanceJudge.closeBelow` and `keepAbove`: the chat assistant asks the user about it.
    case unsure(relevance: Double)
    /// No verdict (no API key, network error, timeout, HTTP error, refusal). The reason is for logs/toasts only.
    case unknown(String)
}

/// Decides whether a page is relevant to the subject the user locked in on (OpenAI Decisions API in production).
/// `subject` is the subject's name; `details` is the user's description of it (`Subject.details`, may be empty).
@MainActor protocol RelevanceJudging: AnyObject {
    func judge(page: PageInfo, subject: String, details: String) async -> RelevanceVerdict
}

/// Asks the user directly when no verdict could be obtained. Returns true to keep the tab ("Needed").
@MainActor protocol NeedPrompting: AnyObject {
    func askIfNeeded(host: String, subject: String) async -> Bool
}
