import AppKit
import SwiftUI

/// Everything the subject form edits, kept apart from the saved Subject so invalid intermediate
/// states (a cleared name, a half-typed URL) never reach the model.
struct SubjectFormState: Equatable {
    var name: String
    var details: String
    var preset: LayoutPreset
    var usesCustomLayout: Bool
    /// One per zone; always at least 2, only the first `preset.siteCount` are shown and saved.
    var zoneSlots: [SetupSlot]
    /// The captured windows of the custom layout, back to front.
    var customSlots: [SetupSlot]
    var browser: Browser
    var unusedApps: UnusedAppsAction
    var allowedApps: [AllowedApp]
    var extraDomains: [String]
    var colorHex: String

    init(subject: Subject?) {
        let custom = subject?.usesCustomLayout ?? false
        name = subject?.name ?? ""
        details = subject?.details ?? ""
        preset = subject?.preset ?? .split
        usesCustomLayout = custom
        zoneSlots = SubjectValidator.zoneSlots((custom ? [] : subject?.slots ?? []).map(Self.editable))
        customSlots = (custom ? subject?.slots ?? [] : []).map(Self.editable)
        browser = subject?.browser ?? .chrome
        unusedApps = subject?.unusedApps ?? .hide
        allowedApps = subject?.allowedApps ?? []
        extraDomains = subject?.extraDomains ?? []
        colorHex = SubjectColor.canonical(subject?.colorHex, name: subject?.name ?? "")
    }

    /// Website windows always show at least one address field.
    static func editable(_ slot: SetupSlot) -> SetupSlot {
        var slot = slot
        if slot.kind == .website && slot.urls.isEmpty { slot.urls = [""] }
        return slot
    }

    var visibleSlots: [SetupSlot] {
        usesCustomLayout ? customSlots : Array(zoneSlots.prefix(preset.siteCount))
    }

    var errors: [String] {
        SubjectValidator.errors(name: name, slots: visibleSlots, customLayout: usesCustomLayout)
    }

    /// The subject as saved (URLs normalized, blanks dropped). Only meaningful when `errors` is empty.
    func subject(id: UUID, createdAt: Date) -> Subject {
        let slots = SubjectValidator.slotsForSave(visibleSlots)
        return Subject(id: id,
                       name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                       details: details.trimmingCharacters(in: .whitespacesAndNewlines),
                       preset: preset,
                       sites: SubjectValidator.sites(of: slots),
                       allowedApps: allowedApps,
                       extraDomains: extraDomains,
                       createdAt: createdAt,
                       slots: slots,
                       usesCustomLayout: usesCustomLayout,
                       browser: browser,
                       unusedApps: unusedApps,
                       colorHex: colorHex)
    }

    func slot(_ id: UUID) -> SetupSlot? {
        customSlots.first { $0.id == id } ?? zoneSlots.first { $0.id == id }
    }

    /// Preset study domains for 1-click website tab setup.
    static let quickSitePresets: [(label: String, url: String)] = [
        ("Canvas", "canvas.illinois.edu"),
        ("GitHub", "github.com"),
        ("arXiv", "arxiv.org"),
        ("Google Docs", "docs.google.com"),
        ("Overleaf", "overleaf.com"),
        ("localhost:3000", "http://localhost:3000"),
    ]

    /// Edits the slot with this id, in whichever list holds it.
    mutating func update(_ id: UUID, _ change: (inout SetupSlot) -> Void) {
        if let index = customSlots.firstIndex(where: { $0.id == id }) {
            change(&customSlots[index])
        } else if let index = zoneSlots.firstIndex(where: { $0.id == id }) {
            change(&zoneSlots[index])
        }
    }

    /// Preset work apps for 1-click allowlist setup (subject to DistractionApps validation).
    static let quickAppPresets: [AllowedApp] = [
        AllowedApp(bundleID: "com.apple.Terminal", name: "Terminal"),
        AllowedApp(bundleID: "com.apple.dt.Xcode", name: "Xcode"),
        AllowedApp(bundleID: "com.microsoft.VSCode", name: "VS Code"),
        AllowedApp(bundleID: "com.todesktop.230313mzl4w4u92", name: "Cursor"),
        AllowedApp(bundleID: "com.apple.Preview", name: "Preview"),
        AllowedApp(bundleID: "com.apple.calculator", name: "Calculator"),
    ]

    /// Adds a non-distraction work app to `allowedApps` if not already present.
    mutating func addQuickAppPreset(_ app: AllowedApp) {
        guard !DistractionApps.isDistraction(app.bundleID),
              !allowedApps.contains(where: { $0.bundleID == app.bundleID }) else { return }
        allowedApps.append(app)
    }

    /// Inserts a quick website preset into `slotID`, replacing an existing empty URL field if one is blank.
    mutating func addQuickSitePreset(_ url: String, to slotID: UUID) {
        update(slotID) { slot in
            guard slot.kind == .website else { return }
            let normalized = url.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { return }
            if slot.urls.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(normalized) == .orderedSame }) {
                return
            }
            if let emptyIndex = slot.urls.firstIndex(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                slot.urls[emptyIndex] = normalized
            } else {
                slot.urls.append(normalized)
            }
        }
    }

    /// Reorders a custom-layout window slot (`back to front`), keeping indices clamped within bounds.
    mutating func moveCustomSlot(from sourceIndex: Int, to destinationIndex: Int) {
        guard customSlots.indices.contains(sourceIndex),
              customSlots.indices.contains(destinationIndex),
              sourceIndex != destinationIndex else { return }
        let slot = customSlots.remove(at: sourceIndex)
        customSlots.insert(slot, at: destinationIndex)
    }

    /// Appends a new centered website window slot up to `SubjectValidator.maxWindows` in Custom layout mode.
    mutating func addCustomSlot() {
        guard customSlots.count < SubjectValidator.maxWindows else { return }
        customSlots.append(SetupSlot.website([""], frame: UnitRect(x: 0.08, y: 0.08, width: 0.84, height: 0.84)))
    }

    /// Trusted reference domain presets for 1-click addition in Allowed sites.
    static let quickAllowedDomainPresets: [(label: String, host: String)] = [
        ("Piazza", "piazza.com"),
        ("EdStem", "edstem.org"),
        ("Stack Overflow", "stackoverflow.com"),
        ("Python Docs", "docs.python.org"),
        ("Wikipedia", "en.wikipedia.org"),
    ]

    /// Validates and appends a safe educational domain preset into `extraDomains`.
    mutating func addAllowedDomainPreset(_ raw: String) {
        guard let host = DomainMatcher.host(of: raw),
              !host.isEmpty,
              !DomainMatcher.isSearchEngine(host),
              DistractionList.category(of: host) == nil,
              !extraDomains.contains(where: { $0.caseInsensitiveCompare(host) == .orderedSame }) else {
            return
        }
        extraDomains.append(host)
    }
}

/// The subject form itself: windows (websites or apps), their layout (a preset or a custom layout
/// captured from the screen), the browser, what happens to other apps, and the allowlists.
/// Shared by the New-subject sheet and the subject page, which edits in place.
struct SubjectForm: View {
    @Binding var form: SubjectFormState
    /// The sheet shows a name field; the subject page edits the name in its title instead.
    var showsName = true
    @State private var siteDraft = ""
    @State private var isPickingApps = false
    /// The window whose app is being chosen.
    @State private var choosingAppFor: SlotRef?
    @State private var captureNote: String?
    @State private var siteNote: String?
    @State private var hasAccessibility = WindowPlacer.isTrusted

    private struct SlotRef: Identifiable {
        let id: UUID
    }

    private var needsAccessibility: Bool {
        !hasAccessibility && (form.usesCustomLayout || form.browser == .arc
                              || form.visibleSlots.contains { $0.kind == .app })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            if showsName { nameSection }
            colorSection
            detailsSection
            layoutSection
            windowsSection
            browserSection
            unusedAppsSection
            appsSection
            sitesAllowedSection
        }
        .sheet(isPresented: $isPickingApps) {
            AppPickerView(selection: $form.allowedApps)
        }
        .sheet(item: $choosingAppFor) { ref in
            AppPickerView(choosing: { app in form.update(ref.id) { $0.app = app } })
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            hasAccessibility = WindowPlacer.isTrusted
        }
    }

    private var nameSection: some View {
        section("Name") {
            TextField("e.g. CS128", text: $form.name)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var colorSection: some View {
        section("Chart color") {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("This color marks the class on the stats chart.")
                    .foregroundStyle(.secondary)
                HStack(spacing: Theme.Space.s) {
                    ForEach(SubjectColor.palette, id: \.self) { hex in
                        Button {
                            form.colorHex = hex
                        } label: {
                            Circle()
                                .fill(Theme.subjectColor(hex))
                                .frame(width: 22, height: 22)
                                .padding(3)
                                .overlay(Circle().stroke(Color.primary, lineWidth: form.colorHex == hex ? 2 : 0))
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Chart color \(hex)")
                    }
                }
            }
        }
    }

    private var detailsSection: some View {
        section("Description") {
            TextEditor(text: $form.details)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(Theme.Space.s)
                .frame(minHeight: 120)
                .background(alignment: .topLeading) {
                    if form.details.isEmpty {
                        Text("e.g. Intro CS in C++: pointers, classes, linked lists. Goal: finish MP3 and study for the midterm.")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, Theme.Space.s + 5)
                            .padding(.vertical, Theme.Space.s)
                    }
                }
                .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Color.primary.opacity(0.15), lineWidth: 1))
                .onChange(of: form.details) { _, text in
                    let capped = SubjectValidator.limitingWords(text)
                    if capped != text { form.details = capped }
                }
            HStack(alignment: .firstTextBaseline) {
                Text("What this subject is and what you're working toward. Tabs you open are checked against it, so a page about the topic stays open even when its title doesn't mention \(form.name.isEmpty ? "the name" : form.name).")
                Spacer(minLength: Theme.Space.m)
                Text("\(SubjectValidator.wordCount(form.details)) / \(SubjectValidator.maxDetailsWords) words")
                    .monospacedDigit()
                    .fixedSize()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: Layout

    private var layoutSection: some View {
        section("Layout") {
            HStack(spacing: Theme.Space.s) {
                ForEach(LayoutPreset.allCases) { option in
                    tile(title: option.title, selected: !form.usesCustomLayout && form.preset == option) {
                        PresetThumbnail(preset: option)
                    } action: {
                        form.preset = option
                        form.usesCustomLayout = false
                    }
                }
                tile(title: "Custom", selected: form.usesCustomLayout) {
                    CustomLayoutThumbnail(slots: form.customSlots)
                } action: {
                    form.usesCustomLayout = true
                }
            }
            if form.usesCustomLayout {
                HStack(spacing: Theme.Space.m) {
                    Button(form.customSlots.isEmpty ? "Capture current windows" : "Capture again") { capture() }
                        .buttonStyle(SecondaryButtonStyle())
                        .fixedSize()
                    Text("Arrange your windows the way you like to work, then capture. The \(SubjectValidator.maxWindows) frontmost windows on your main screen are copied with their position, websites, or app and folder.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let captureNote {
                    Text(captureNote).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func tile<Thumb: View>(title: String, selected: Bool, @ViewBuilder thumbnail: () -> Thumb,
                                   action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: Theme.Space.s) {
                thumbnail().frame(width: 92)
                Text(title).font(.caption)
            }
            .padding(Theme.Space.s)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius)
                    .stroke(Color.primary.opacity(selected ? 1 : 0.15), lineWidth: selected ? 2 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func capture() {
        let captured = WorkspaceCapture.capture()
        form.customSlots = captured.slots.map(SubjectFormState.editable)
        if let found = captured.browser { form.browser = found }
        if captured.slots.isEmpty {
            captureNote = "No windows found on the main screen."
        } else if !WindowPlacer.isTrusted && captured.slots.contains(where: { $0.kind == .app }) {
            captureNote = "Captured \(captured.slots.count) windows. Allow Accessibility to also capture each app's folder."
        } else {
            captureNote = "Captured \(captured.slots.count) windows. Check them below."
        }
    }

    // MARK: Windows

    private var windowsSection: some View {
        section(form.usesCustomLayout
                ? "Windows (back to front)"
                : (form.preset.siteCount == 1 ? "Window" : "Windows, left to right")) {
            ForEach(Array(form.visibleSlots.enumerated()), id: \.element.id) { index, slot in
                slotEditor(slot, number: index + 1)
            }
            if form.usesCustomLayout && form.customSlots.count < SubjectValidator.maxWindows {
                Button("+ Add Window") {
                    form.addCustomSlot()
                }
                .buttonStyle(SecondaryButtonStyle())
                .font(.caption)
            }
            Text(form.usesCustomLayout
                 ? "Each window opens where it was captured; a mini timer floats on top."
                 : (form.preset.appHasZone
                    ? "Each window fills its zone; this app takes the remaining zone."
                    : "Each window fills its zone; a mini timer floats on top."))
                .font(.caption)
                .foregroundStyle(.secondary)
            if needsAccessibility {
                HStack(spacing: Theme.Space.s) {
                    Image(systemName: "hand.raised")
                    Text("Placing app\(form.browser == .arc ? " and Arc" : "") windows needs Accessibility permission.")
                        .font(.caption)
                    Spacer()
                    Button("Allow…") {
                        WindowPlacer.requestAccess()
                        hasAccessibility = WindowPlacer.isTrusted
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .fixedSize()
                }
                .foregroundStyle(.secondary)
            }
        }
    }

    private func slotEditor(_ slot: SetupSlot, number: Int) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack {
                Text("Window \(number)").font(.callout.weight(.semibold))
                Picker("", selection: kindBinding(slot.id)) {
                    Text("Website").tag(SetupSlot.Kind.website)
                    Text("App").tag(SetupSlot.Kind.app)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 160)
                Spacer()
                if form.usesCustomLayout {
                    if form.customSlots.count > 1 {
                        let idx = number - 1
                        HStack(spacing: 4) {
                            Button {
                                form.moveCustomSlot(from: idx, to: idx - 1)
                            } label: {
                                Image(systemName: "chevron.up")
                                    .font(.caption.weight(.bold))
                            }
                            .buttonStyle(.borderless)
                            .disabled(idx == 0)
                            .help("Move window earlier (back)")

                            Button {
                                form.moveCustomSlot(from: idx, to: idx + 1)
                            } label: {
                                Image(systemName: "chevron.down")
                                    .font(.caption.weight(.bold))
                            }
                            .buttonStyle(.borderless)
                            .disabled(idx >= form.customSlots.count - 1)
                            .help("Move window later (front)")
                        }
                    }
                    Button {
                        form.customSlots.removeAll { $0.id == slot.id }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove this window")
                }
            }
            switch slot.kind {
            case .website: websiteFields(slot)
            case .app: appFields(slot)
            }
        }
        .padding(Theme.Space.m)
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Color.primary.opacity(0.15)))
    }

    private func websiteFields(_ slot: SetupSlot) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            ForEach(slot.urls.indices, id: \.self) { index in
                HStack {
                    TextField(index == 0 ? "e.g. cs128.org" : "Extra tab, e.g. prairielearn.org",
                              text: urlBinding(slot.id, index))
                        .textFieldStyle(.roundedBorder)
                    if index > 0 {
                        Button {
                            form.update(slot.id) { if index < $0.urls.count { $0.urls.remove(at: index) } }
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove this tab")
                    }
                }
            }
            Button("Add tab") { form.update(slot.id) { $0.urls.append("") } }
                .buttonStyle(.borderless)
                .font(.caption)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Space.xs) {
                    Text("Quick add:")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    ForEach(SubjectFormState.quickSitePresets, id: \.url) { preset in
                        let alreadyAdded = slot.urls.contains {
                            $0.trimmingCharacters(in: .whitespacesAndNewlines).localizedCaseInsensitiveContains(preset.url)
                        }
                        Button("+ \(preset.label)") {
                            form.addQuickSitePreset(preset.url, to: slot.id)
                        }
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(alreadyAdded ? Theme.emerald.opacity(0.14) : Color.primary.opacity(0.06)))
                        .foregroundStyle(alreadyAdded ? Theme.emerald : .secondary)
                        .buttonStyle(.plain)
                        .disabled(alreadyAdded)
                    }
                }
            }
        }
    }

    private func appFields(_ slot: SetupSlot) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(spacing: Theme.Space.s) {
                if let app = slot.app {
                    AppIcon(bundleID: app.bundleID).frame(width: 22, height: 22)
                    Text(app.name)
                } else {
                    Text("No app chosen").foregroundStyle(.secondary)
                }
                Spacer()
                Button(slot.app == nil ? "Choose app…" : "Change…") { choosingAppFor = SlotRef(id: slot.id) }
                    .buttonStyle(SecondaryButtonStyle())
                    .fixedSize()
            }
            HStack(spacing: Theme.Space.s) {
                TextField("Folder to open (optional), e.g. ~/code/cs128", text: folderBinding(slot.id))
                    .textFieldStyle(.roundedBorder)
                Button("Choose…") { chooseFolder(for: slot.id) }
                    .buttonStyle(.borderless)
            }
        }
    }

    private func chooseFolder(for id: UUID) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "The folder (or file) the app opens when you lock in"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        form.update(id) { $0.folder = (url.path as NSString).abbreviatingWithTildeInPath }
    }

    // MARK: Browser and other apps

    private var browserSection: some View {
        section("Browser for websites") {
            Picker("", selection: $form.browser) {
                ForEach(Browser.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 280)
            if NSWorkspace.shared.urlForApplication(withBundleIdentifier: form.browser.bundleID) == nil {
                Text("\(form.browser.title) isn't installed on this Mac.").font(.caption).foregroundStyle(.secondary)
            } else if form.browser == .arc {
                Text("Pinned Arc tabs are left alone. Tabs in every space are checked, including ones opened after you lock in.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var unusedAppsSection: some View {
        section("Other apps while locked in") {
            Picker("", selection: $form.unusedApps) {
                ForEach(UnusedAppsAction.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 280)
            Text(form.unusedApps == .quit
                 ? "Apps the setup doesn't use are asked to quit (they can ask to save first). At the end you choose which ones to open again. Finder, Terminal, Xcode and Cursor are only hidden."
                 : "Apps the setup doesn't use are hidden and shown again when the session ends.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var appsSection: some View {
        section("Allowed apps") {
            if form.allowedApps.isEmpty {
                Text("None. Only \(form.browser.title), Finder and the setup's own apps stay available. Apps you unblock during a session are saved here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(form.allowedApps) { app in
                    HStack(spacing: Theme.Space.s) {
                        AppIcon(bundleID: app.bundleID).frame(width: 20, height: 20)
                        Text(app.name)
                        Spacer()
                        Button {
                            form.allowedApps.removeAll { $0.bundleID == app.bundleID }
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.borderless)
                        .help("Stop allowing \(app.name)")
                    }
                }
            }
            HStack(spacing: Theme.Space.s) {
                Button("Add apps…") { isPickingApps = true }
                    .buttonStyle(SecondaryButtonStyle())
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Space.xs) {
                        ForEach(SubjectFormState.quickAppPresets.filter {
                            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleID) != nil
                        }) { preset in
                            let alreadyAdded = form.allowedApps.contains { $0.bundleID == preset.bundleID }
                            Button("+ \(preset.name)") {
                                form.addQuickAppPreset(preset)
                            }
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(alreadyAdded ? Theme.emerald.opacity(0.14) : Color.primary.opacity(0.06)))
                            .foregroundStyle(alreadyAdded ? Theme.emerald : .secondary)
                            .buttonStyle(.plain)
                            .disabled(alreadyAdded)
                        }
                    }
                }
            }
            Text("High-distraction apps (Discord, Telegram, Slack, Steam, games, social media) are automatically blocked during focus sessions and cannot be unlocked mid-session by the assistant.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var sitesAllowedSection: some View {
        section("Allowed sites") {
            Text("Left open during this work block, and remembered for next time. The sites in the windows above are already allowed; sites you allow during a session are saved here.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(form.extraDomains, id: \.self) { host in
                HStack(spacing: Theme.Space.s) {
                    Image(systemName: "globe").frame(width: 20)
                    Text(host).lineLimit(1)
                    Spacer()
                    Button { form.extraDomains.removeAll { $0 == host } } label: { Image(systemName: "xmark") }
                        .buttonStyle(.borderless)
                        .help("Stop allowing \(host)")
                }
            }
            HStack(spacing: Theme.Space.s) {
                TextField("Add a site, e.g. piazza.com", text: $siteDraft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addAllowedSite)
                Button("Add") { addAllowedSite() }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(siteDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Space.xs) {
                    Text("Trusted presets:")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    ForEach(SubjectFormState.quickAllowedDomainPresets, id: \.host) { preset in
                        let alreadyAdded = form.extraDomains.contains { $0.caseInsensitiveCompare(preset.host) == .orderedSame }
                        Button("+ \(preset.label)") {
                            form.addAllowedDomainPreset(preset.host)
                        }
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(alreadyAdded ? Theme.emerald.opacity(0.14) : Color.primary.opacity(0.06)))
                        .foregroundStyle(alreadyAdded ? Theme.emerald : .secondary)
                        .buttonStyle(.plain)
                        .disabled(alreadyAdded)
                    }
                }
            }
            if let siteNote {
                Text(siteNote)
                    .font(.caption)
                    .foregroundStyle(Theme.amber)
            }
        }
    }

    private func addAllowedSite() {
        let raw = siteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let host = DomainMatcher.host(of: raw), !host.isEmpty else {
            siteNote = "Enter a valid website domain (e.g. arxiv.org or piazza.com)."
            return
        }
        if DomainMatcher.isSearchEngine(host) {
            siteNote = "Search engines (\(host)) stay query-judged per search; academic queries stay open automatically."
            return
        }
        if let category = DistractionList.category(of: host), category != .video {
            siteNote = "\(host) is blocked under Distraction Shield (\(category.rawValue))."
            return
        }
        siteNote = nil
        if !form.extraDomains.contains(where: { DomainMatcher.normalize($0) == host }) {
            form.extraDomains.append(host)
        }
        siteDraft = ""
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text(title).font(Theme.captionFont).foregroundStyle(.secondary)
            content()
        }
    }

    // MARK: Slot bindings

    private func kindBinding(_ id: UUID) -> Binding<SetupSlot.Kind> {
        Binding(get: { form.slot(id)?.kind ?? .website }, set: { kind in
            form.update(id) { slot in
                slot.kind = kind
                if kind == .website && slot.urls.isEmpty { slot.urls = [""] }
            }
        })
    }

    private func urlBinding(_ id: UUID, _ index: Int) -> Binding<String> {
        Binding(get: {
            guard let urls = form.slot(id)?.urls, index < urls.count else { return "" }
            return urls[index]
        }, set: { text in
            form.update(id) { if index < $0.urls.count { $0.urls[index] = text } }
        })
    }

    private func folderBinding(_ id: UUID) -> Binding<String> {
        Binding(get: { form.slot(id)?.folder ?? "" }, set: { text in form.update(id) { $0.folder = text } })
    }
}

/// Sheet for creating a subject. Existing subjects are edited in place on their own page.
struct SubjectEditorView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var form = SubjectFormState(subject: nil)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    Text("New subject").font(.title2.weight(.semibold))
                    SubjectForm(form: $form)
                }
                .padding(Theme.Space.l)
            }
            Divider()
            footer.padding(Theme.Space.l)
        }
        .frame(width: 660, height: 780)
    }

    private var footer: some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                ForEach(form.errors, id: \.self) { message in
                    Text(message).font(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(SecondaryButtonStyle())
                .keyboardShortcut(.cancelAction)
            Button("Save") { save() }
                .buttonStyle(PrimaryButtonStyle())
                .frame(width: 120)
                .opacity(form.errors.isEmpty ? 1 : 0.35)
                .disabled(!form.errors.isEmpty)
                .keyboardShortcut(.defaultAction)
        }
    }

    private func save() {
        guard form.errors.isEmpty else { return }
        model.addSubject(form.subject(id: UUID(), createdAt: Date()))
        dismiss()
    }
}
