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
    /// Domains closed without a verdict (`DistractionList.hosts` in production), protected tabs included.
    private let alwaysBlocked: [String]

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

    init(studySites: [String], protected: Set<String>, alwaysBlocked: [String] = []) {
        // Never allow bare search engines (e.g. legacy "google.com" in extraDomains) to disable query judging.
        self.studyDomains = DomainMatcher.allowedDomains(sites: studySites, extra: [])
            .filter { !DomainMatcher.isSearchEngine($0) }
        self.protected = protected
        self.alwaysBlocked = alwaysBlocked.map(DomainMatcher.normalize)
    }

    /// Tabs that need a relevance verdict now, in the given order. Skips Chrome internals, blank and
    /// unparseable URLs, study sites, protected pre-existing tabs, URLs already decided / in flight / awaiting the
    /// user or the assistant, and hosts that have an answer. Every returned URL is marked in flight, so it is returned once.
    mutating func tabsToCheck(_ tabs: [ChromeTab]) -> [ChromeTab] {
        var result: [ChromeTab] = []
        for tab in tabs {
            guard isCandidate(tab), !isAlwaysBlocked(tab),
                  !keptURLs.contains(tab.url), !closeURLs.contains(tab.url),
                  !inFlightURLs.contains(tab.url), !awaitingPromptURLs.contains(tab.url),
                  !awaitingAssistantURLs.contains(tab.url), !isHostAnswered(tab) else { continue }
            inFlightURLs.insert(tab.url)
            result.append(tab)
        }
        return result
    }

    /// Stores the outcome of one check. Relevant: keep. Off-task: close now and whenever the URL reappears.
    /// Unknown: the check no longer runs for this URL; the controller asks in the chat popup, same as unsure.
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

    /// True when the tab can be closed without another check: its host or media bypass is always blocked, its URL
    /// was judged off-task, or the user said "Close tab" for its host. Never true for study sites, Chrome internals
    /// or hosts the user said are needed; protected pre-existing tabs are only closed when always blocked.
    func shouldCloseImmediately(_ tab: ChromeTab) -> Bool {
        guard let host = DomainMatcher.host(of: tab.url) else { return false }
        if neededHosts.contains(host) { return false }
        if isAlwaysBlocked(tab) { return true }
        guard isCandidate(tab) else { return false }
        return closeURLs.contains(tab.url) || closedHosts.contains(host)
    }

    /// An http(s) tab on an always-blocked domain (or search-engine video/media bypass when video is blocked)
    /// that is not one of the study sites.
    func isAlwaysBlocked(_ tab: ChromeTab) -> Bool {
        guard !alwaysBlocked.isEmpty,
              !DomainMatcher.isAllowed(tab.url, allowed: studyDomains),
              let host = DomainMatcher.host(of: tab.url),
              !DistractionList.matches(host, any: DistractionList.exceptions) else { return false }
        if DistractionList.matches(host, any: alwaysBlocked) { return true }
        if DomainMatcher.isSearchVideoOrMediaBypass(tab.url) {
            // Mirror YouTube blocking: if youtube.com isn't explicitly allowed by study sites or the user,
            // Google/Bing/DuckDuckGo video preview modals & video tabs cannot bypass the block.
            let videoAllowed = neededHosts.contains("youtube.com")
                || DomainMatcher.isAllowed("https://youtube.com/", allowed: studyDomains)
            return !videoAllowed || !alwaysBlocked.contains("youtube.com")
        }
        return false
    }

    /// Stores the user's answer for `host`. A newer answer replaces an older one.
    /// General search engines (`google.com`, etc.) are never added to `neededHosts` or `closedHosts` because
    /// each search query has distinct relevance.
    mutating func recordAnswer(host: String, needed: Bool) {
        let host = DomainMatcher.normalize(host)
        guard !host.isEmpty, !DomainMatcher.isSearchEngine(host) else { return }
        if needed {
            if !alwaysBlocked.isEmpty && DistractionList.matches(host, any: alwaysBlocked) {
                if let cat = DistractionList.category(of: host), cat != .video {
                    return
                }
            }
            neededHosts.insert(host)
            closedHosts.remove(host)
        } else {
            closedHosts.insert(host)
            neededHosts.remove(host)
        }
    }

    /// Keeps one specific URL (e.g. an allowed search query) without whitelisting the entire search host.
    mutating func keepURL(_ url: String) {
        inFlightURLs.remove(url)
        awaitingPromptURLs.remove(url)
        awaitingAssistantURLs.remove(url)
        closeURLs.remove(url)
        keptURLs.insert(url)
    }

    /// Marks one specific URL as off-task (e.g. a rejected search query) without banning the entire search host.
    mutating func closeURL(_ url: String) {
        inFlightURLs.remove(url)
        awaitingPromptURLs.remove(url)
        awaitingAssistantURLs.remove(url)
        keptURLs.remove(url)
        closeURLs.insert(url)
    }

    /// Keeps every tab on `host` for the rest of the session (the chat assistant allowed the site).
    mutating func allowHost(_ host: String) {
        recordAnswer(host: host, needed: true)
    }

    /// Closes every tab on `host`, now and whenever it is opened again this session (the chat assistant closed the site).
    mutating func closeHost(_ host: String) {
        recordAnswer(host: host, needed: false)
    }

    /// A study site, a bare search engine homepage, a judged-relevant URL, or a host the user allowed during this block.
    /// Everything else is closed when a break ends.
    func isRelated(_ tab: ChromeTab) -> Bool {
        if DomainMatcher.isAllowed(tab.url, allowed: studyDomains) { return true }
        if isAlwaysBlocked(tab) { return false }
        if DomainMatcher.isSearchEngineHomepage(tab.url) { return true }
        if keptURLs.contains(tab.url) { return true }
        guard let host = DomainMatcher.host(of: tab.url) else { return false }
        return neededHosts.contains(host)
    }

    /// True when the tab's host has an answer (kept or closed), so its URLs need no verdict.
    func isHostAnswered(_ tab: ChromeTab) -> Bool {
        guard let host = DomainMatcher.host(of: tab.url) else { return false }
        return neededHosts.contains(host) || closedHosts.contains(host)
    }

    /// Not a Chrome internal / blank / unparseable page, not a study site, not a protected pre-existing tab,
    /// and not a bare search engine homepage.
    private func isCandidate(_ tab: ChromeTab) -> Bool {
        !protected.contains(ChromeScripts.protectionKey(tab))
            && !DomainMatcher.isAllowed(tab.url, allowed: studyDomains)
            && !DomainMatcher.isSearchEngineHomepage(tab.url)
    }
}
