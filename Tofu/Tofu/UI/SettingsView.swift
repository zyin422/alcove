import SwiftUI

/// Settings (spec §11): profile, Discord bot, give-up phrase, relevance check (OpenAI key), Chrome automation, demo data.
/// Used both as the sidebar's Settings detail and in the app's Settings scene.
struct SettingsView: View {
    let model: AppModel

    /// Discord application id, only used to build the invite link. Not a secret, so UserDefaults is fine.
    @AppStorage("discordAppID") private var discordAppID = ""
    @State private var tokenDraft = ""
    @State private var tokenSource = TokenSource.none
    @State private var openAIKeyDraft = ""
    @State private var openAIKeySource = TokenSource.none
    @State private var discordStatus = ""
    @State private var isTesting = false
    @State private var chromeStatus = SettingsStatus.chromeUnchecked
    @State private var isRequestingChrome = false
    @State private var hasAccessibility = WindowPlacer.isTrusted
    /// True while a Google sign-in is in flight, so Connect can't start a second one.
    @State private var isConnectingGoogle = false
    /// Chrome's Automation permission as macOS reports it without prompting; refreshed when Settings appears.
    @State private var chromePermission = AutomationPermission.appNotRunning
    /// Mirrors TofuApp's menu-bar timer switch.
    @AppStorage("menuBarTimer") private var menuBarTimer = true

    var body: some View {
        Form {
            setupSection
            profileSection
            menuBarSection
            discordSection
            discordSetupSection
            googleSection
            accountabilitySection
            companionSection
            endOfDaySection
            relevanceSection
            chromeSection
            accessibilitySection
            demoSection
        }
        .formStyle(.grouped)
        .frame(minWidth: 480, idealWidth: 560, minHeight: 480, idealHeight: 720)
        .navigationTitle("Settings")
        .onAppear(perform: refresh)
    }

    // MARK: - Sections

    /// What a lock-in depends on, at a glance. Details and fixes live in the sections below.
    private var setupSection: some View {
        let items = SetupCheck.items(SetupCheck.Inputs(
            accessibility: hasAccessibility, chrome: chromePermission, openAIKey: openAIKeySource,
            discordEnabled: model.data.settings.discordEnabled, discordToken: tokenSource,
            googleConnected: model.isGoogleConnected))
        return Section {
            ForEach(items) { item in
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                    Image(systemName: Self.symbol(for: item.state))
                        .foregroundStyle(item.state == .needsAction ? Color.primary : Color.secondary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                        Text(item.detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(item.title): \(Self.stateName(item.state)). \(item.detail)")
            }
        } header: {
            HStack {
                Text("Setup check")
                Spacer()
                Text(SetupCheck.summary(items)).foregroundStyle(.secondary)
                Button("Recheck", action: refresh).buttonStyle(.link)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
    }

    private static func symbol(for state: SetupCheck.State) -> String {
        switch state {
        case .ready: "checkmark.circle.fill"
        case .optional: "circle.dashed"
        case .needsAction: "exclamationmark.triangle.fill"
        case .unknown: "questionmark.circle"
        }
    }

    private static func stateName(_ state: SetupCheck.State) -> String {
        switch state {
        case .ready: "ready"
        case .optional: "optional"
        case .needsAction: "needs action"
        case .unknown: "unknown"
        }
    }

    private var profileSection: some View {
        Section {
            TextField("Display name", text: displayName)
        } header: {
            Text("Profile")
        } footer: {
            Text("Shown in Discord messages, e.g. “\(model.data.settings.displayName) is locked in on CS128”.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var menuBarSection: some View {
        Section {
            Toggle("Show the timer in the menu bar while locked in", isOn: $menuBarTimer)
        } header: {
            Text("Menu bar")
        } footer: {
            Text("The time left (or so far) stays visible even when Tofu's own windows are hidden. Its menu brings Tofu forward or ends the session.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var discordSection: some View {
        Section {
            Toggle("Post lock-ins to Discord", isOn: discordEnabled)
            HStack {
                SecureField("Bot token", text: $tokenDraft)
                    .onSubmit(saveToken)
                Button("Save", action: saveToken)
                    .disabled(SettingsStatus.cleanedToken(tokenDraft) == nil)
            }
            HStack {
                Label(tokenSource.label, systemImage: tokenIcon)
                Spacer()
                if tokenSource == .keychain {
                    Button("Remove", action: removeToken)
                }
            }
            HStack(spacing: Theme.Space.s) {
                Button("Test connection", action: testConnection)
                    .disabled(tokenSource == .none || isTesting)
                if isTesting {
                    ProgressView().controlSize(.small)
                }
                Text(discordStatus)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        } header: {
            Text("Discord")
        } footer: {
            Text("The bot posts when you lock in, finish, or bail. It uses #locked-in when that channel exists (#lock-in, #lockin and #accountability also work), including after it has been posting in #general. Bots can't join group DMs. A token you save here overrides the team token bundled from .env.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var discordSetupSection: some View {
        Section("Discord setup") {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("1. Create an application at [discord.com/developers/applications](https://discord.com/developers/applications).")
                Text("2. Open **Bot**, click **Reset Token**, copy the token and paste it above, then click Save.")
                Text("3. Copy the **Application ID** from General Information into the field below and open the invite link.")
                Text("4. In your server, create a text channel named **#lock-in** (#locked-in, #lockin and #accountability also work).")
            }
            .fixedSize(horizontal: false, vertical: true)
            TextField("Application ID", text: $discordAppID)
            if let url = SettingsStatus.inviteURL(appID: discordAppID) {
                Link("Invite the bot to a server", destination: url)
            } else {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    if !discordAppID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("The Application ID is a number, e.g. 1234567890123456789.")
                    }
                    Text(SettingsStatus.inviteTemplate)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
                .foregroundStyle(.secondary)
            }
        }
    }

    private var googleSection: some View {
        Section {
            if model.isGoogleConnected {
                Label("Connected", systemImage: "checkmark.circle.fill")
                Toggle("Sync tasks with Google Tasks", isOn: googleTasksSyncEnabled)
                Toggle("Log sessions to Google Calendar", isOn: googleSessionLogEnabled)
                Toggle("Show today's events", isOn: googleShowEventsEnabled)
                Button("Disconnect") { model.disconnectGoogle() }
            } else {
                HStack(spacing: Theme.Space.s) {
                    Button("Connect Google…", action: connectGoogle)
                        .disabled(isConnectingGoogle)
                    Text(model.googleStatus)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Google")
        } footer: {
            Text("Today's plan mirrors your default Google Tasks list, finished sessions are logged to a “Tofu” calendar, and today's events show on the morning screen. Sign-in shows “UIUC Collective Mind” — that's the shared app this uses. If Google disconnects you after a week, just connect again.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var accountabilitySection: some View {
        Section {
            TextField("Give-up phrase", text: giveUpTemplate)
            LabeledContent("Preview") {
                Text("“\(SettingsStatus.phrasePreview(template: model.data.settings.giveUpTemplate))”")
            }
        } header: {
            Text("Accountability")
        } footer: {
            Text("With an API key, ending a goal early opens the Mirror, and the session stops only if you confirm a forfeit. This phrase is the fallback with no key. {subject} becomes the subject name.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var companionSection: some View {
        Section {
            Toggle("Show the study companion", isOn: companionEnabled)
            Picker("Personality", selection: companionPersonality) {
                ForEach(CompanionPersonality.allCases) { personality in
                    Text(personality.title).tag(personality)
                }
            }
            .disabled(!model.data.settings.companionEnabled)
            Button("Open images folder") {
                CompanionArt.ensureDirectory()
                NSWorkspace.shared.open(CompanionArt.imagesDirectory())
            }
        } header: {
            Text("Study companion")
        } footer: {
            Text("She floats bottom-right while you're locked in, cheers you on, and calls you out when something gets blocked. Drop your own character art into the images folder as neutral.png, annoyed.png, pleased.png and dark.png (transparent PNGs look best); without them the included Emilia portraits are used. “Tsundere → yandere” turns dark after \(CompanionScript.escalationThreshold) blocked attempts in a session.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var endOfDaySection: some View {
        Section {
            Toggle("Show the morning screen", isOn: Binding(
                get: { model.data.settings.morningScreenEnabled },
                set: { value in model.updateSettings { $0.morningScreenEnabled = value } }))
            Toggle("Ask me to wrap up the day", isOn: dayEndPromptEnabled)
            DatePicker("At", selection: dayEndTime, displayedComponents: .hourAndMinute)
                .disabled(!model.data.settings.dayEndPromptEnabled)
        } header: {
            Text("End of day")
        } footer: {
            Text("The morning screen shows the first time you use the Mac each day (after 4 AM): pick one of today's priorities and lock in on its setup. At the end-of-day time the app asks what you finished, posts it to the group chat, and has you say tomorrow's priorities. If you're locked in, it waits until the session ends. You can also use “Wrap up” on the Today page.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var relevanceSection: some View {
        Section {
            HStack {
                SecureField("OpenAI API key", text: $openAIKeyDraft)
                    .onSubmit(saveOpenAIKey)
                Button("Save", action: saveOpenAIKey)
                    .disabled(SettingsStatus.cleanedToken(openAIKeyDraft) == nil)
            }
            HStack {
                Label(openAIKeySource.keyLabel, systemImage: openAIKeyIcon)
                Spacer()
                if openAIKeySource == .keychain {
                    Button("Remove", action: removeOpenAIKey)
                }
            }
        } header: {
            Text("Relevance check (OpenAI)")
        } footer: {
            Text("While locked in, tab URLs and titles are sent to OpenAI to check relevance. Tabs unrelated to your subject are closed; when a page can't be checked you're asked instead. A key you save here overrides the team key bundled from .env.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var chromeSection: some View {
        Section {
            LabeledContent("Automation") {
                Text(chromeStatus)
                    .multilineTextAlignment(.trailing)
            }
            Button("Request access", action: requestChromeAccess)
                .disabled(isRequestingChrome)
        } header: {
            Text("Chrome")
        } footer: {
            Text("macOS asks once: “Tofu wants to control Google Chrome.” Allow it so study sites open and off-topic tabs close. Arc asks the same the first time a setup uses it.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var accessibilitySection: some View {
        Section {
            LabeledContent("Accessibility") {
                Text(hasAccessibility ? "Allowed" : "Not allowed")
            }
            HStack {
                Button("Request access") {
                    WindowPlacer.requestAccess()
                    hasAccessibility = WindowPlacer.isTrusted
                }
                .disabled(hasAccessibility)
                Button("Open System Settings") { NSWorkspace.shared.open(WindowPlacer.settingsURL) }
            }
        } header: {
            Text("Window placement")
        } footer: {
            Text("Needed to place app windows (e.g. VS Code on a project folder), Arc windows and custom layouts, and to capture each app's folder. A switch left on for an older copy does not cover this one — remove that row, then allow it again.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            hasAccessibility = WindowPlacer.isTrusted
        }
    }

    private var demoSection: some View {
        let demoCount = model.data.sessions.filter(\.isDemo).count
        return Section {
            Text(SettingsStatus.demoSummary(count: demoCount))
            HStack {
                Button("Load demo data") { model.loadDemoData() }
                    .disabled(demoCount > 0)
                Button("Clear demo data") { model.clearDemoData() }
                    .disabled(demoCount == 0)
            }
            HStack {
                Button("Show morning screen") { model.showMorning() }
                Button("Post day recap to Discord") { model.postDayRecap() }
            }
        } header: {
            Text("Demo")
        } footer: {
            Text("Load adds about 30 days of sample sessions (and CS128 and MATH241 if you have no subjects) so Stats looks full. Clear removes the sample sessions again. Show morning screen opens the start-of-day splash. Post day recap sends today’s done and not-done priorities, plus tomorrow’s list, to Discord.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Bindings

    private var displayName: Binding<String> {
        Binding(get: { model.data.settings.displayName },
                set: { newValue in model.updateSettings { $0.displayName = newValue } })
    }

    private var discordEnabled: Binding<Bool> {
        Binding(get: { model.data.settings.discordEnabled },
                set: { newValue in model.updateSettings { $0.discordEnabled = newValue } })
    }

    private var companionEnabled: Binding<Bool> {
        Binding(get: { model.data.settings.companionEnabled },
                set: { newValue in model.updateSettings { $0.companionEnabled = newValue } })
    }

    private var googleTasksSyncEnabled: Binding<Bool> {
        Binding(get: { model.data.settings.googleTasksSyncEnabled },
                set: { newValue in model.updateSettings { $0.googleTasksSyncEnabled = newValue } })
    }

    private var googleSessionLogEnabled: Binding<Bool> {
        Binding(get: { model.data.settings.googleSessionLogEnabled },
                set: { newValue in model.updateSettings { $0.googleSessionLogEnabled = newValue } })
    }

    private var googleShowEventsEnabled: Binding<Bool> {
        Binding(get: { model.data.settings.googleShowEventsEnabled },
                set: { newValue in model.updateSettings { $0.googleShowEventsEnabled = newValue } })
    }

    private var companionPersonality: Binding<CompanionPersonality> {
        Binding(get: { model.data.settings.companionPersonality },
                set: { newValue in model.updateSettings { $0.companionPersonality = newValue } })
    }

    private var dayEndPromptEnabled: Binding<Bool> {
        Binding(get: { model.data.settings.dayEndPromptEnabled },
                set: { newValue in model.updateSettings { $0.dayEndPromptEnabled = newValue } })
    }

    /// `dayEndMinutes` shown as a time of day (today's date, which is ignored).
    private var dayEndTime: Binding<Date> {
        Binding(get: {
            let minutes = model.data.settings.dayEndMinutes % (24 * 60)
            return Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
        }, set: { newValue in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            var minutes = (parts.hour ?? 22) * 60 + (parts.minute ?? 0)
            if minutes < DayKey.dayStartHour * 60 { minutes += 24 * 60 }
            model.updateSettings { $0.dayEndMinutes = minutes }
        })
    }

    private var giveUpTemplate: Binding<String> {
        Binding(get: { model.data.settings.giveUpTemplate },
                set: { newValue in model.updateSettings { $0.giveUpTemplate = newValue } })
    }

    // MARK: - Actions

    private var tokenIcon: String {
        switch tokenSource {
        case .keychain: "lock.fill"
        case .teamFile: "doc.text"
        case .none: "key"
        }
    }

    private var openAIKeyIcon: String {
        switch openAIKeySource {
        case .keychain: "lock.fill"
        case .teamFile: "doc.text"
        case .none: "key"
        }
    }

    private func refresh() {
        tokenSource = model.discordTokenSource
        openAIKeySource = model.openAIKeySource
        hasAccessibility = WindowPlacer.isTrusted
        if !ChromeController.isInstalled {
            chromeStatus = SettingsStatus.chromeResult(.notInstalled)
        }
        Task {
            chromePermission = await Task.detached {
                AutomationPermission.check(bundleID: Browser.chrome.bundleID)
            }.value
        }
    }

    /// Saves to the Keychain, which overrides the team token.
    private func saveToken() {
        guard let token = SettingsStatus.cleanedToken(tokenDraft) else { return }
        model.setDiscordToken(token)
        tokenDraft = ""
        tokenSource = model.discordTokenSource
        discordStatus = ""
    }

    /// Deletes the Keychain token; the team token (if bundled) applies again.
    private func removeToken() {
        model.setDiscordToken(nil)
        tokenSource = model.discordTokenSource
        discordStatus = ""
    }

    /// Saves to the Keychain, which overrides the team key.
    private func saveOpenAIKey() {
        guard let key = SettingsStatus.cleanedToken(openAIKeyDraft) else { return }
        model.setOpenAIKey(key)
        openAIKeyDraft = ""
        openAIKeySource = model.openAIKeySource
    }

    /// Deletes the Keychain key; the team key (if bundled) applies again.
    private func removeOpenAIKey() {
        model.setOpenAIKey(nil)
        openAIKeySource = model.openAIKeySource
    }

    /// Starts the Google sign-in; Connect stays disabled until it finishes.
    private func connectGoogle() {
        isConnectingGoogle = true
        Task { @MainActor in
            await model.connectGoogle()
            isConnectingGoogle = false
        }
    }

    /// GET /users/@me then /users/@me/guilds with the saved token; shows the result text.
    private func testConnection() {
        guard let token = model.discordToken else {
            discordStatus = SettingsStatus.noToken
            return
        }
        isTesting = true
        discordStatus = SettingsStatus.testing
        Task { @MainActor in
            let client = DiscordClient(token: token)
            let result: Result<(user: DiscordUser, guildCount: Int), Error>
            do {
                let user = try await client.me()
                let guilds = try await client.guilds()
                result = .success((user: user, guildCount: guilds.count))
            } catch {
                result = .failure(error)
            }
            discordStatus = SettingsStatus.discordResult(result)
            isTesting = false
        }
    }

    /// Runs the harmless ping script, which makes macOS show the Automation prompt the first time.
    private func requestChromeAccess() {
        isRequestingChrome = true
        chromeStatus = SettingsStatus.chromeWaiting
        Task { @MainActor in
            // Let the waiting text render first: the Apple Event blocks until the prompt is answered.
            try? await Task.sleep(nanoseconds: 150_000_000)
            chromeStatus = SettingsStatus.chromeResult(ChromeController.requestAccess())
            isRequestingChrome = false
        }
    }
}
