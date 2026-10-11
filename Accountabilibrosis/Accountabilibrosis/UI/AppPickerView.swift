import AppKit
import SwiftUI

/// Sheet that edits a subject's allowed apps: installed apps with icon, name, search and checkmarks.
/// With `onChoose` (the `choosing:` init) it picks a single app instead and closes on the first tap.
struct AppPickerView: View {
    @Binding var selection: [AllowedApp]
    private var onChoose: ((AllowedApp) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var apps: [AllowedApp] = []
    @State private var query = ""
    @State private var isLoading = true

    init(selection: Binding<[AllowedApp]>) {
        _selection = selection
    }

    /// Picks one app (e.g. the app a setup window opens); every installed app is offered.
    init(choosing onChoose: @escaping (AllowedApp) -> Void) {
        _selection = .constant([])
        self.onChoose = onChoose
    }

    /// Always allowed during every session, so never offered as an allowed app.
    private var excluded: Set<String> {
        let own: Set<String> = [Bundle.main.bundleIdentifier ?? "com.accountabilibrosis.app"]
        return onChoose == nil ? BlockPolicy.alwaysAllowed.union(own) : own
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text(onChoose == nil ? "Allowed apps" : "Choose an app").font(.title2.weight(.semibold))
            Text(onChoose == nil ? "Google Chrome and Finder are always allowed, so they are not listed."
                                 : "It opens in this window of the setup when you lock in.")
                .font(.callout)
                .foregroundStyle(.secondary)
            TextField("Search apps", text: $query)
                .textFieldStyle(.roundedBorder)
            List(AppCatalog.filter(apps, query: query, excluding: excluded)) { app in
                Button {
                    toggle(app)
                } label: {
                    HStack(spacing: Theme.Space.s) {
                        AppIcon(bundleID: app.bundleID).frame(width: 22, height: 22)
                        Text(app.name)
                        Spacer()
                        if isSelected(app) {
                            Image(systemName: "checkmark").fontWeight(.semibold)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .overlay {
                if isLoading {
                    ProgressView()
                }
            }
            HStack {
                if onChoose == nil {
                    Text("\(selection.count) selected").foregroundStyle(.secondary)
                }
                Spacer()
                Button(onChoose == nil ? "Done" : "Cancel") { dismiss() }
                    .buttonStyle(PrimaryButtonStyle())
                    .frame(width: 120)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.Space.l)
        .frame(width: 460, height: 580)
        .task { await load() }
    }

    private func isSelected(_ app: AllowedApp) -> Bool {
        selection.contains { $0.bundleID == app.bundleID }
    }

    private func toggle(_ app: AllowedApp) {
        if let onChoose {
            onChoose(app)
            dismiss()
        } else if isSelected(app) {
            selection.removeAll { $0.bundleID == app.bundleID }
        } else {
            selection.append(app)
        }
    }

    /// Scans the app folders off the main thread.
    private func load() async {
        let found = await Task.detached(priority: .userInitiated) {
            AppCatalog.scan(directories: AppCatalog.defaultDirectories())
        }.value
        apps = found
        isLoading = false
    }
}

/// An installed app's icon in grayscale (the UI stays monochrome), or a placeholder if it is not installed.
struct AppIcon: View {
    let bundleID: String

    var body: some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .saturation(0)
        } else {
            Image(systemName: "app.dashed")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.secondary)
        }
    }
}
