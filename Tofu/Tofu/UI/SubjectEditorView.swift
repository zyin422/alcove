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
                       unusedApps: unusedApps)
    }

    func slot(_ id: UUID) -> SetupSlot? {
        customSlots.first { $0.id == id } ?? zoneSlots.first { $0.id == id }
    }

    /// Edits the slot with this id, in whichever list holds it.
    mutating func update(_ id: UUID, _ change: (inout SetupSlot) -> Void) {
        if let index = customSlots.firstIndex(where: { $0.id == id }) {
            change(&customSlots[index])
        } else if let index = zoneSlots.firstIndex(where: { $0.id == id }) {
            change(&zoneSlots[index])
        }
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
            Button("Add apps…") { isPickingApps = true }
                .buttonStyle(SecondaryButtonStyle())
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
                Button("Add") { addAllowedSite() }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(siteDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func addAllowedSite() {
        let raw = siteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let host = DomainMatcher.host(of: raw), !host.isEmpty else { return }
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
