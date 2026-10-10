import SwiftUI

/// Settings (spec §11): profile, Discord bot, give-up phrase, Chrome automation, demo data.
/// Used both as the sidebar's Settings detail and in the app's Settings scene.
struct SettingsView: View {
    let model: AppModel

    /// Discord application id, only used to build the invite link. Not a secret, so UserDefaults is fine.
    @AppStorage("discordAppID") private var discordAppID = ""
    @State private var tokenDraft = ""
    @State private var hasToken = false
    @State private var discordStatus = ""
    @State private var isTesting = false
    @State private var chromeStatus = SettingsStatus.chromeUnchecked
    @State private var isRequestingChrome = false

    var body: some View {
        Form {
            profileSection
            discordSection
            discordSetupSection
            accountabilitySection
            chromeSection
            demoSection
        }
        .formStyle(.grouped)
        .frame(minWidth: 480, idealWidth: 560, minHeight: 480, idealHeight: 720)
        .navigationTitle("Settings")
        .onAppear(perform: refresh)
    }

    // MARK: - Sections

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

    private var discordSection: some View {
        Section {
            Toggle("Post lock-ins to Discord", isOn: discordEnabled)
            HStack {
                SecureField("Bot token", text: $tokenDraft)
                    .onSubmit(saveToken)
                Button("Save", action: saveToken)
                    .disabled(SettingsStatus.cleanedToken(tokenDraft) == nil)
            }
            if hasToken {
                HStack {
                    Label("Token saved in Keychain", systemImage: "lock.fill")
                    Spacer()
                    Button("Remove", action: removeToken)
                }
            }
            HStack(spacing: Theme.Space.s) {
                Button("Test connection", action: testConnection)
                    .disabled(!hasToken || isTesting)
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
            Text("The bot posts when you lock in, finish, or bail. Bots can't join group DMs, so it posts in one text channel per server it is in.")
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
            Text("Ending a goal session early means typing this phrase. {subject} becomes the subject name.")
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
            Text("macOS asks once: “Accountabilibrosis wants to control Google Chrome.” Allow it so study sites open and off-topic tabs close. No Accessibility permission is needed.")
                .font(.caption)
                .foregroundStyle(.secondary)
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
        } header: {
            Text("Demo")
        } footer: {
            Text("Load adds about 30 days of sample sessions (and CS128 and MATH241 if you have no subjects) so Stats looks full. Clear removes the sample sessions again.")
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

    private var giveUpTemplate: Binding<String> {
        Binding(get: { model.data.settings.giveUpTemplate },
                set: { newValue in model.updateSettings { $0.giveUpTemplate = newValue } })
    }

    // MARK: - Actions

    private func refresh() {
        hasToken = model.discordToken != nil
        if !ChromeController.isInstalled {
            chromeStatus = SettingsStatus.chromeResult(.notInstalled)
        }
    }

    private func saveToken() {
        guard let token = SettingsStatus.cleanedToken(tokenDraft) else { return }
        model.setDiscordToken(token)
        tokenDraft = ""
        hasToken = model.discordToken != nil
        discordStatus = ""
    }

    private func removeToken() {
        model.setDiscordToken(nil)
        hasToken = model.discordToken != nil
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
            chromeStatus = SettingsStatus.chromeResult(ChromeController().requestAccess())
            isRequestingChrome = false
        }
    }
}
