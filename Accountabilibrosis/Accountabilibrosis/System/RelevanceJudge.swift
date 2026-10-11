import Foundation

/// Judges one page against the locked-in subject with the OpenAI Decisions API (`DecisionsClient`).
/// Pages without a description or site name are first enriched by fetching their HTML head (`PageMetadata`).
/// No caching here: the tab watch remembers verdicts.
@MainActor final class RelevanceJudge: RelevanceJudging {
    /// Close the tab when the off-task probability is at least this.
    static let threshold = 0.5

    private let apiKey: () -> String?
    private let transport: HTTPTransport
    private let metadataFetcher: (String) async -> PageMetadata.Fields

    /// `apiKey` is read on every check, so a key saved in Settings applies immediately.
    /// `metadataFetcher` (tests) replaces the default fetch of the page itself through `transport`.
    init(apiKey: @escaping () -> String?, transport: HTTPTransport = URLSessionTransport(),
         metadataFetcher: ((String) async -> PageMetadata.Fields)? = nil) {
        self.apiKey = apiKey
        self.transport = transport
        self.metadataFetcher = metadataFetcher ?? { url in await PageMetadata.fetch(url: url, transport: transport) }
    }

    func judge(page: PageInfo, subject: String) async -> RelevanceVerdict {
        guard let key = apiKey()?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            return .unknown("No OpenAI API key")
        }
        var page = page
        if page.description == nil && page.siteName == nil {
            let metadata = await metadataFetcher(page.url)
            page.description = metadata.description
            page.siteName = metadata.siteName
            if page.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let title = metadata.title {
                page.title = title
            }
        }
        do {
            let probability = try await DecisionsClient(apiKey: key, transport: transport)
                .offTaskProbability(page: page, subject: subject)
            return probability >= Self.threshold ? .offTask : .relevant
        } catch {
            return .unknown(String(describing: error))
        }
    }
}
