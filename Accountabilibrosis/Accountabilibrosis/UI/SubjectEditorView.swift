import SwiftUI

/// Sheet for creating (`subject == nil`) or editing a subject.
struct SubjectEditorView: View {
    let model: AppModel
    private let original: Subject?
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var preset: LayoutPreset
    /// Always at least 2 slots; only the first `preset.siteCount` are shown and saved.
    @State private var sites: [String]
    @State private var allowedApps: [AllowedApp]
    @State private var extraDomainsText: String
    @State private var isPickingApps = false

    init(model: AppModel, subject: Subject?) {
        self.model = model
        self.original = subject
        _name = State(initialValue: subject?.name ?? "")
        _preset = State(initialValue: subject?.preset ?? .split)
        _sites = State(initialValue: SubjectValidator.siteSlots(subject?.sites ?? []))
        _allowedApps = State(initialValue: subject?.allowedApps ?? [])
        _extraDomainsText = State(initialValue: (subject?.extraDomains ?? []).joined(separator: ", "))
    }

    private var visibleSites: [String] { Array(sites.prefix(preset.siteCount)) }
    private var errors: [String] { SubjectValidator.errors(name: name, sites: visibleSites, preset: preset) }
    private var parsedDomains: [String] { SubjectValidator.parseDomains(extraDomainsText) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    Text(original == nil ? "New subject" : "Edit subject").font(.title2.weight(.semibold))
                    nameSection
                    presetSection
                    sitesSection
                    appsSection
                    domainsSection
                }
                .padding(Theme.Space.l)
            }
            Divider()
            footer.padding(Theme.Space.l)
        }
        .frame(width: 600, height: 680)
        .sheet(isPresented: $isPickingApps) {
            AppPickerView(selection: $allowedApps)
        }
    }

    private var nameSection: some View {
        section("Name") {
            TextField("e.g. CS128", text: $name)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var presetSection: some View {
        section("Layout") {
            HStack(spacing: Theme.Space.m) {
                ForEach(LayoutPreset.allCases) { option in
                    Button {
                        preset = option
                    } label: {
                        VStack(spacing: Theme.Space.s) {
                            PresetThumbnail(preset: option).frame(width: 100)
                            Text(option.title).font(.caption)
                        }
                        .padding(Theme.Space.s)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.radius)
                                .stroke(Color.primary.opacity(preset == option ? 1 : 0.15),
                                        lineWidth: preset == option ? 2 : 1)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(preset == option ? .isSelected : [])
                }
            }
        }
    }

    private var sitesSection: some View {
        section(preset.siteCount == 1 ? "Site" : "Sites") {
            ForEach(0..<preset.siteCount, id: \.self) { index in
                TextField(index == 0 ? "e.g. cs128.org" : "e.g. prairielearn.org", text: $sites[index])
                    .textFieldStyle(.roundedBorder)
            }
            Text(preset.appHasZone
                 ? "Each site opens in its own Chrome window; this app takes the remaining zone."
                 : "Each site opens in its own Chrome window; a mini timer floats on top.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var appsSection: some View {
        section("Allowed apps") {
            if allowedApps.isEmpty {
                Text("None. Only Google Chrome and Finder stay available.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(allowedApps) { app in
                    HStack(spacing: Theme.Space.s) {
                        AppIcon(bundleID: app.bundleID).frame(width: 20, height: 20)
                        Text(app.name)
                        Spacer()
                        Button {
                            allowedApps.removeAll { $0.bundleID == app.bundleID }
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove \(app.name)")
                    }
                }
            }
            Button("Add apps…") { isPickingApps = true }
                .buttonStyle(SecondaryButtonStyle())
        }
    }

    private var domainsSection: some View {
        section("Extra allowed sites") {
            TextField("e.g. piazza.com, stackoverflow.com", text: $extraDomainsText)
                .textFieldStyle(.roundedBorder)
            Text(parsedDomains.isEmpty
                 ? "Comma-separated. Subdomains are included."
                 : "Allows: " + parsedDomains.joined(separator: ", "))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                ForEach(errors, id: \.self) { message in
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
                .opacity(errors.isEmpty ? 1 : 0.35)
                .disabled(!errors.isEmpty)
                .keyboardShortcut(.defaultAction)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text(title).font(Theme.captionFont).foregroundStyle(.secondary)
            content()
        }
    }

    private func save() {
        guard errors.isEmpty else { return }
        let subject = Subject(id: original?.id ?? UUID(),
                              name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                              preset: preset,
                              sites: SubjectValidator.sitesForSave(visibleSites, preset: preset),
                              allowedApps: allowedApps,
                              extraDomains: parsedDomains,
                              createdAt: original?.createdAt ?? Date())
        if original == nil {
            model.addSubject(subject)
        } else {
            model.updateSubject(subject)
        }
        dismiss()
    }
}
