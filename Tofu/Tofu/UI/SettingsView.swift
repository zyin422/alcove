import SwiftUI

/// Settings (spec §11): setup check, profile, Discord bot, give-up phrase, companion, screen memory, end of day,
/// Chrome automation and window placement. Used both as the sidebar's Settings detail and in the app's Settings
/// scene (⌘,), the usual macOS pair. The Google account lives on Connections, not here. The OpenAI key is
/// resolved silently by AppModel (bundled `.env`, else Keychain), so there is no field for it.
struct SettingsView: View {
    let model: AppModel

    /// Discord application id, only used to build the invite link. Not a secret, so UserDefaults is fine.
    @AppStorage("discordAppID") private var discordAppID = ""
    @State private var tokenDraft = ""
    @State private var tokenSource = TokenSource.none
    /// Only read by the setup check (screen memory needs a key).
    @State private var openAIKeySource = TokenSource.none
    @State private var discordStatus = ""
    @State private var isTesting = false
    @State private var chromeStatus = SettingsStatus.chromeUnchecked
    @State private var isRequestingChrome = false
    @State private var hasAccessibility = WindowPlacer.isTrusted
    /// Chrome's Automation permission as macOS reports it without prompting; refreshed when Settings appears.
    @State private var chromePermission = AutomationPermission.appNotRunning
    @State private var hasScreenRecording = CGPreflightScreenCaptureAccess()
    @State private var isConfirmingForget = false
    /// Both Tofu Do Not Disturb shortcuts are installed (read with `shortcuts list` when Settings appears).
    @State private var hasDoNotDisturbShortcuts = false
    @State private var isAddingShortcuts = false
    /// Mirrors TofuApp's menu-bar timer switch.
    @AppStorage("menuBarTimer") private var menuBarTimer = true

    var body: some View {
        Form {
            setupSection
            profileSection
            menuBarSection
            discordSection
            discordSetupSection
            accountabilitySection
            companionSection
            screenMemorySection
            doNotDisturbSection
            endOfDaySection
            chromeSection
            accessibilitySection
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
            googleConnected: model.isGoogleConnected,
            screenMemoryEnabled: model.data.settings.screenMemoryEnabled, screenRecording: hasScreenRecording,
            googleServices: GoogleService.allCases.filter { model.googleState(of: $0) == .on },
            googleNotGranted: GoogleService.allCases.filter { model.googleState(of: $0) == .notGranted },
            doNotDisturbShortcuts: hasDoNotDisturbShortcuts))
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
            Text("The time left (or so far) stays visible even when Tofu's own windows are hidden. To bring Tofu forward or end the session, use the mini timer or the End button.")
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
        } header: {
            Text("Study companion")
        } footer: {
            Text("Moss, a small forest spirit, sits bottom-right while you're locked in. It greets you, keeps you company, cheers at the halfway mark, and gently calls out what gets blocked — a little firmer after \(CompanionScript.concernThreshold) distractions in a session. With screen memory on, it reminds you where you left off.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// The only place that opens Shortcuts: Tofu never does it on its own (it used to on every launch).
    private var doNotDisturbSection: some View {
        Section {
            LabeledContent("Shortcuts") {
                Text(hasDoNotDisturbShortcuts ? "Added" : "Not added")
            }
            Button(isAddingShortcuts ? "Opening Shortcuts…" : "Add Do Not Disturb shortcuts…", action: addShortcuts)
                .disabled(hasDoNotDisturbShortcuts || isAddingShortcuts)
        } header: {
            Text("Do Not Disturb")
        } footer: {
            Text("Tofu turns on Do Not Disturb for each work block and off when it ends, through two shortcuts: “\(DoNotDisturbPlan.onName)” and “\(DoNotDisturbPlan.offName)”. The button opens Shortcuts so you can add them; a Focus you turned on yourself is left alone.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var screenMemorySection: some View {
        Section {
            Toggle("Remember what I work on", isOn: Binding(
                get: { model.data.settings.screenMemoryEnabled },
                set: { value in model.updateSettings { $0.screenMemoryEnabled = value } }))
            LabeledContent("Screen Recording") {
                Text(hasScreenRecording ? "Allowed" : "Not allowed")
            }
            HStack {
                Button("Allow screen recording") {
                    hasScreenRecording = ScreenCapturer.requestPermission()
                }
                .disabled(hasScreenRecording)
                Button("Open System Settings") { NSWorkspace.shared.open(ScreenCapturer.settingsURL) }
            }
            LabeledContent("Remembered") {
                Text(model.memory.notes.count == 1 ? "1 note" : "\(model.memory.notes.count) notes")
            }
            Button("Forget everything…", role: .destructive) { isConfirmingForget = true }
                .disabled(model.memory.notes.isEmpty)
                .confirmationDialog("Forget every screen memory note?", isPresented: $isConfirmingForget) {
                    Button("Forget everything", role: .destructive) { model.memory.forgetAll() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Moss and the assistants will no longer know where you left off.")
                }
        } header: {
            Text("Screen memory")
        } footer: {
            Text("While you're locked in, Tofu takes a screenshot of your main display every 5 minutes (Tofu's own windows left out) and sends it to OpenAI to be described in a sentence or two. Only that description is kept, in memory.json on this Mac; the screenshot is never saved. Moss, the chat assistant and the setup agent use the notes to remind you where you left off. Breaks are never captured. Each subject's notes are listed on its page, where you can delete them.")
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

    /// Opens the two shortcut files in Shortcuts for the user to add, and remembers that setup was offered,
    /// so a work block no longer shows the setup hint.
    private func addShortcuts() {
        isAddingShortcuts = true
        UserDefaults.standard.set(true, forKey: DoNotDisturbPlan.hintShownKey)
        Task {
            let opened = await Task.detached { DoNotDisturbShortcuts.install() }.value
            isAddingShortcuts = false
            if !opened { ToastCenter.shared.show("Couldn't open Shortcuts. Try again in a moment.") }
        }
    }

    private func refresh() {
        tokenSource = model.discordTokenSource
        openAIKeySource = model.openAIKeySource
        hasAccessibility = WindowPlacer.isTrusted
        hasScreenRecording = CGPreflightScreenCaptureAccess()
        Task {
            hasDoNotDisturbShortcuts = await Task.detached { DoNotDisturbShortcuts.isInstalled() }.value
        }
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
