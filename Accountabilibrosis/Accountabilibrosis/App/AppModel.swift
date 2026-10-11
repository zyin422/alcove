import AppKit
import Foundation
import Observation

/// What the main window's sidebar has selected.
enum SidebarItem: Hashable {
    case subject(UUID)
    case stats
    case settings
}

/// Where the Discord bot token in use comes from.
enum TokenSource: Equatable {
    /// The token saved in Settings (Keychain). It overrides the team token.
    case keychain
    /// The team token bundled from the repo's `.env` at build time.
    case teamFile
    case none

    /// Shown next to the token field in Settings.
    var label: String {
        switch self {
        case .keychain: "Using your token from Keychain"
        case .teamFile: "Using the team token from .env"
        case .none: "No token"
        }
    }

    /// Shown next to the OpenAI key field in Settings (the same three sources as the Discord token).
    var keyLabel: String {
        switch self {
        case .keychain: "Using your key from Keychain"
        case .teamFile: "Using the team key from .env"
        case .none: "No key — you'll be asked about each site"
        }
    }
}

/// Root app state: the persisted data, the sidebar selection and the session engine.
/// Every mutation saves `data` to the store right away.
@Observable @MainActor final class AppModel {
    var data: StoreData
    var selection: SidebarItem?
    let store: Store
    let engine: SessionEngine
    /// Where the two possible bot tokens come from (the Keychain, the bundled `.env`); tests inject fakes.
    private let keychainToken: () -> String?
    private let envToken: () -> String?
    /// Same two places for the OpenAI API key.
    private let keychainOpenAIKey: () -> String?
    private let envOpenAIKey: () -> String?

    /// Loads store (shows warning toast if any), builds live engine with real controllers.
    convenience init(store: Store = Store(fileURL: Store.defaultURL())) {
        let (loaded, isFirstLaunch) = Self.load(store)
        // The announcer and the relevance judge need the model, but the model needs the engine (which needs
        // them). Their closures read the model through this box, which is filled in after init.
        let box = ModelBox()
        let announcer = DiscordAnnouncer(
            token: { box.model?.discordToken },
            settings: { box.model?.data.settings ?? AppSettings(discordEnabled: false) },
            onCacheUpdate: { cache in box.model?.updateSettings { $0.channelCache = cache } },
            toaster: ToastCenter.shared)
        let judge = RelevanceJudge(apiKey: { [box] in box.model?.openAIKey })
        let engine = SessionEngine(workspace: WorkspaceController(), blocker: AppBlocker(),
                                   chrome: ChromeController(judge: judge, prompter: NeedPrompt()),
                                   toaster: ToastCenter.shared,
                                   announcer: announcer,
                                   ownBundleID: Bundle.main.bundleIdentifier ?? "com.accountabilibrosis.app",
                                   visibleFrame: { ScreenGeometry.mainVisibleFrame() },
                                   primaryHeight: { ScreenGeometry.primaryHeight() })
        self.init(store: store, loaded: loaded, isFirstLaunch: isFirstLaunch, engine: engine,
                  keychainToken: { Keychain.get(service: Secrets.discordService, account: Secrets.discordAccount) },
                  envToken: { EnvFile.bundledValue(AppModel.envTokenKey) },
                  keychainOpenAIKey: { Keychain.get(service: Secrets.openAIService, account: Secrets.openAIAccount) },
                  envOpenAIKey: { EnvFile.bundledValue(AppModel.envOpenAIKeyName) })
        box.model = self
        if let warning = loaded.warning {
            // After launch, so the toast panel can find the screen.
            DispatchQueue.main.async { ToastCenter.shared.show(warning) }
        }
    }

    /// Test initializer: injected engine. The token and key sources default to "nothing", so tests never
    /// read the real Keychain or the bundled `.env`.
    convenience init(store: Store, engine: SessionEngine,
                     keychainToken: @escaping () -> String? = { nil },
                     envToken: @escaping () -> String? = { nil },
                     keychainOpenAIKey: @escaping () -> String? = { nil },
                     envOpenAIKey: @escaping () -> String? = { nil }) {
        let (loaded, isFirstLaunch) = Self.load(store)
        self.init(store: store, loaded: loaded, isFirstLaunch: isFirstLaunch, engine: engine,
                  keychainToken: keychainToken, envToken: envToken,
                  keychainOpenAIKey: keychainOpenAIKey, envOpenAIKey: envOpenAIKey)
    }

    private init(store: Store, loaded: StoreLoadResult, isFirstLaunch: Bool, engine: SessionEngine,
                 keychainToken: @escaping () -> String?, envToken: @escaping () -> String?,
                 keychainOpenAIKey: @escaping () -> String?, envOpenAIKey: @escaping () -> String?) {
        self.store = store
        self.engine = engine
        self.keychainToken = keychainToken
        self.envToken = envToken
        self.keychainOpenAIKey = keychainOpenAIKey
        self.envOpenAIKey = envOpenAIKey
        self.data = loaded.data
        self.selection = loaded.data.subjects.first.map { SidebarItem.subject($0.id) }
        engine.onSessionChanged = { [weak self] session in
            self?.upsertSession(session)
        }
        // First launch with a token already available (team .env or Keychain): start posting to Discord.
        if isFirstLaunch, discordToken != nil {
            data.settings.discordEnabled = true
            save()
        }
    }

    /// Loads the store and reports whether there was no store file before (a first launch).
    private static func load(_ store: Store) -> (result: StoreLoadResult, isFirstLaunch: Bool) {
        let existed = FileManager.default.fileExists(atPath: store.fileURL.path)
        return (store.load(), !existed)
    }

    // MARK: Subjects

    func subject(id: UUID) -> Subject? {
        data.subjects.first { $0.id == id }
    }

    /// Appends the subject, selects it and saves.
    func addSubject(_ subject: Subject) {
        data.subjects.append(subject)
        selection = .subject(subject.id)
        save()
    }

    /// Replaces the subject with the same id (no-op if it is unknown) and saves.
    func updateSubject(_ subject: Subject) {
        guard let index = data.subjects.firstIndex(where: { $0.id == subject.id }) else { return }
        data.subjects[index] = subject
        save()
    }

    /// Removes the subject but keeps its sessions (stats use their `subjectName` snapshot).
    func deleteSubject(id: UUID) {
        data.subjects.removeAll { $0.id == id }
        if selection == .subject(id) {
            selection = data.subjects.first.map { SidebarItem.subject($0.id) }
        }
        save()
    }

    // MARK: Sessions

    /// Inserts a new session or replaces the one with the same id, then saves.
    func upsertSession(_ session: Session) {
        if let index = data.sessions.firstIndex(where: { $0.id == session.id }) {
            data.sessions[index] = session
        } else {
            data.sessions.append(session)
        }
        save()
    }

    /// Starts a session on the subject using the display name from settings.
    func lockIn(subjectID: UUID, mode: SessionMode) async {
        guard let subject = subject(id: subjectID) else { return }
        let trimmed = data.settings.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = trimmed.isEmpty ? NSFullUserName() : trimmed
        await engine.start(subject: subject, mode: mode, displayName: displayName)
    }

    // MARK: Settings

    func updateSettings(_ mutate: (inout AppSettings) -> Void) {
        mutate(&data.settings)
        save()
    }

    /// Writes `data` to the store. A failure is shown as a toast; the in-memory data stays intact.
    func save() {
        do {
            try store.save(data)
        } catch {
            NSLog("Accountabilibrosis: saving failed: %@", error.localizedDescription)
            ToastCenter.shared.show("Couldn't save your data: \(error.localizedDescription)")
        }
    }

    /// Key of the team's bot token in the bundled `.env`.
    static let envTokenKey = "DISCORD_BOT_TOKEN"

    /// Picks the bot token: a non-empty Keychain token wins, else the team token from `.env`.
    /// Blank strings count as missing, and the winner is trimmed.
    nonisolated static func resolveToken(keychain: String?, env: String?) -> (token: String?, source: TokenSource) {
        func cleaned(_ raw: String?) -> String? {
            let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let token = cleaned(keychain) { return (token, .keychain) }
        if let token = cleaned(env) { return (token, .teamFile) }
        return (nil, .none)
    }

    private var resolvedToken: (token: String?, source: TokenSource) {
        Self.resolveToken(keychain: keychainToken(), env: envToken())
    }

    /// The Discord bot token in use: the Keychain token, else the team token. Never stored in store.json.
    var discordToken: String? { resolvedToken.token }

    /// Which of the two tokens `discordToken` is.
    var discordTokenSource: TokenSource { resolvedToken.source }

    /// Saves a trimmed token to the Keychain (it then overrides the team token); nil or blank deletes it.
    func setDiscordToken(_ token: String?) {
        let trimmed = (token ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            Keychain.delete(service: Secrets.discordService, account: Secrets.discordAccount)
        } else {
            Keychain.set(trimmed, service: Secrets.discordService, account: Secrets.discordAccount)
        }
    }

    /// Key of the OpenAI API key in the bundled `.env`.
    static let envOpenAIKeyName = "OPENAI_API_KEY"

    private var resolvedOpenAIKey: (token: String?, source: TokenSource) {
        Self.resolveToken(keychain: keychainOpenAIKey(), env: envOpenAIKey())
    }

    /// The OpenAI key used for the relevance check: the Keychain key, else the team key from `.env`.
    /// Never stored in store.json. Without one every check gives no verdict and the user is asked instead.
    var openAIKey: String? { resolvedOpenAIKey.token }

    /// Which of the two keys `openAIKey` is.
    var openAIKeySource: TokenSource { resolvedOpenAIKey.source }

    /// Saves a trimmed key to the Keychain (it then overrides the team key); nil or blank deletes it.
    func setOpenAIKey(_ key: String?) {
        let trimmed = (key ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            Keychain.delete(service: Secrets.openAIService, account: Secrets.openAIAccount)
        } else {
            Keychain.set(trimmed, service: Secrets.openAIService, account: Secrets.openAIAccount)
        }
    }

    // MARK: Demo data

    /// Adds CS128 and MATH241 when there are no subjects, then (re)seeds about 30 days of demo sessions.
    /// Earlier demo sessions are replaced, so loading twice never duplicates them.
    func loadDemoData() {
        let now = Date()
        if data.subjects.isEmpty {
            data.subjects = DemoData.defaultSubjects(now: now)
            if selection == nil {
                selection = data.subjects.first.map { SidebarItem.subject($0.id) }
            }
        }
        data.sessions.removeAll { $0.isDemo }
        data.sessions.append(contentsOf: DemoData.generate(subjects: data.subjects, now: now))
        save()
    }

    /// Removes every demo session. Subjects and real sessions are kept.
    func clearDemoData() {
        data.sessions.removeAll { $0.isDemo }
        save()
    }
}

/// Weak link from the live DiscordAnnouncer's closures back to the model (see `AppModel.init(store:)`).
@MainActor private final class ModelBox {
    weak var model: AppModel?
}
