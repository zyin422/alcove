import Foundation

/// Bookkeeping for the relevance-checked tab watch (pure; the controller owns the I/O).
/// Decides, poll after poll, which tabs still need a verdict, which can be closed without asking again,
/// and remembers the user's "Needed" / "Close tab" answers (and the chat assistant's allow / close decisions)
/// per host for the rest of the session.
/// Tabs are tracked by exact URL, so a tab that navigates somewhere new is judged again.
struct TabTriage {
    /// Normalized hosts of the subject's study sites. These (and their subdomains) are never judged or closed.
    private let studyDomains: [String]
    /// Protection keys (`ChromeScripts.protectionKey`) of tabs that existed before the session started.
    private let protected: Set<String>

    /// URLs judged relevant: kept.
    private var keptURLs: Set<String> = []
    /// URLs judged off-task: closed whenever they show up again, without a new verdict.
    private var closeURLs: Set<String> = []
    /// URLs handed out by `tabsToCheck` whose verdict has not come back yet.
    private var inFlightURLs: Set<String> = []
    /// URLs whose check gave no verdict; the user is asked about their host instead.
    private var awaitingPromptURLs: Set<String> = []
    /// URLs judged "unsure": kept open while the chat assistant asks the user about their host.
    private var awaitingAssistantURLs: Set<String> = []
    /// Hosts the user answered "Needed" for (or the assistant allowed): kept for the session.
    private var neededHosts: Set<String> = []
    /// Hosts the user answered "Close tab" for (or the assistant closed): every tab on them is closed for the session.
    private var closedHosts: Set<String> = []

    init(studySites: [String], protected: Set<String>) {
        self.studyDomains = DomainMatcher.allowedDomains(sites: studySites, extra: [])
        self.protected = protected
    }

    /// Tabs that need a relevance verdict now, in the given order. Skips Chrome internals, blank and
    /// unparseable URLs, study sites, protected pre-existing tabs, URLs already decided / in flight / awaiting the
    /// user or the assistant, and hosts that have an answer. Every returned URL is marked in flight, so it is returned once.
    mutating func tabsToCheck(_ tabs: [ChromeTab]) -> [ChromeTab] {
        var result: [ChromeTab] = []
        for tab in tabs {
            guard isCandidate(tab),
                  !keptURLs.contains(tab.url), !closeURLs.contains(tab.url),
                  !inFlightURLs.contains(tab.url), !awaitingPromptURLs.contains(tab.url),
                  !awaitingAssistantURLs.contains(tab.url), !isHostAnswered(tab) else { continue }
            inFlightURLs.insert(tab.url)
            result.append(tab)
        }
        return result
    }

    /// Stores the outcome of one check. Relevant: keep. Off-task: close now and whenever the URL reappears.
    /// Unknown: the check no longer runs for this URL; the controller asks the user about the host.
    /// Unsure: the tab stays open and is not checked again; the controller hands the host to the chat assistant,
    /// whose `allowHost` / `closeHost` decision settles it.
    mutating func record(url: String, verdict: RelevanceVerdict) {
        inFlightURLs.remove(url)
        switch verdict {
        case .relevant: keptURLs.insert(url)
        case .offTask: closeURLs.insert(url)
        case .unknown: awaitingPromptURLs.insert(url)
        case .unsure: awaitingAssistantURLs.insert(url)
        }
    }

    /// True when the tab can be closed without another check: its URL was judged off-task, or the user said
    /// "Close tab" for its host. Never true for study sites, Chrome internals, protected tabs or hosts the
    /// user said are needed.
    func shouldCloseImmediately(_ tab: ChromeTab) -> Bool {
        guard isCandidate(tab) else { return false }
        guard let host = DomainMatcher.host(of: tab.url) else { return false }
        if neededHosts.contains(host) { return false }
        return closeURLs.contains(tab.url) || closedHosts.contains(host)
    }

    /// Stores the user's answer for `host`. A newer answer replaces an older one.
    mutating func recordAnswer(host: String, needed: Bool) {
        let host = DomainMatcher.normalize(host)
        guard !host.isEmpty else { return }
        if needed {
            neededHosts.insert(host)
            closedHosts.remove(host)
        } else {
            closedHosts.insert(host)
            neededHosts.remove(host)
        }
    }

    /// Keeps every tab on `host` for the rest of the session (the chat assistant allowed the site).
    mutating func allowHost(_ host: String) {
        recordAnswer(host: host, needed: true)
    }

    /// Closes every tab on `host`, now and whenever it is opened again this session (the chat assistant closed the site).
    mutating func closeHost(_ host: String) {
        recordAnswer(host: host, needed: false)
    }

    /// True when the tab's host has an answer (kept or closed), so its URLs need no verdict.
    func isHostAnswered(_ tab: ChromeTab) -> Bool {
        guard let host = DomainMatcher.host(of: tab.url) else { return false }
        return neededHosts.contains(host) || closedHosts.contains(host)
    }

    /// Not a Chrome internal / blank / unparseable page, not a study site, not a protected pre-existing tab.
    private func isCandidate(_ tab: ChromeTab) -> Bool {
        !protected.contains(ChromeScripts.protectionKey(tab))
            && !DomainMatcher.isAllowed(tab.url, allowed: studyDomains)
    }
}
