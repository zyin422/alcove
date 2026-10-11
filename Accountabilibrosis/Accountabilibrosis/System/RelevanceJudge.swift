import Foundation

/// STUB — replaced by the Decisions API implementation (DecisionsClient + PageMetadata).
@MainActor final class RelevanceJudge: RelevanceJudging {
    /// Close the tab when the off-task probability is at least this.
    static let threshold = 0.5

    /// `apiKey` is read on every check, so a key saved in Settings applies immediately.
    init(apiKey: @escaping () -> String?, transport: HTTPTransport = URLSessionTransport()) {}

    func judge(page: PageInfo, subject: String) async -> RelevanceVerdict {
        .unknown("not implemented")
    }
}
