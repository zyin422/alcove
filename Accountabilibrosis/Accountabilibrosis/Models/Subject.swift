import Foundation

/// How the screen is split between the setup's windows (zones) and our app while locked in.
enum LayoutPreset: String, Codable, CaseIterable, Identifiable {
    case split      // zone | zone + mini timer
    case full       // zone + mini timer
    case thirds     // App | zone | zone
    case mainSide   // zone 70% | App 30%

    var id: String { rawValue }
    /// Number of zones (each holds a website window or an app).
    var siteCount: Int { (self == .split || self == .thirds) ? 2 : 1 }
    var appHasZone: Bool { self == .thirds || self == .mainSide }
    var title: String {
        switch self {
        case .split: return "Left / Right"
        case .full: return "Full"
        case .thirds: return "Thirds"
        case .mainSide: return "70 / 30"
        }
    }
}

/// An app the user may keep using during a subject's session (in addition to the always-allowed set).
struct AllowedApp: Codable, Hashable, Identifiable {
    var bundleID: String
    var name: String
    var id: String { bundleID }
}

/// The browser a setup's websites open in. Both are driven with AppleScript; Arc has no window bounds,
/// so its windows are placed with Accessibility instead.
enum Browser: String, Codable, CaseIterable, Identifiable {
    case chrome
    case arc

    var id: String { rawValue }
    var title: String {
        switch self {
        case .chrome: return "Google Chrome"
        case .arc: return "Arc"
        }
    }
    /// Name used in `tell application "…"`.
    var scriptName: String {
        switch self {
        case .chrome: return "Google Chrome"
        case .arc: return "Arc"
        }
    }
    var bundleID: String {
        switch self {
        case .chrome: return "com.google.Chrome"
        case .arc: return "company.thebrowser.Browser"
        }
    }
    /// Chrome windows take `bounds`; Arc's don't.
    var supportsBounds: Bool { self == .chrome }
    /// Chrome tab ids are integers; Arc's are text (and must be quoted in scripts).
    var hasTextTabIDs: Bool { self == .arc }
    /// Chrome windows can be minimized and restored by script; Arc fails every such request.
    var canMinimizeWindows: Bool { self == .chrome }
}

/// What happens to apps the setup doesn't use, from lock-in until the session ends.
enum UnusedAppsAction: String, Codable, CaseIterable, Identifiable {
    /// Hidden, and shown again at the end.
    case hide
    /// Asked to quit (they may ask to save), and opened again at the end.
    case quit

    var id: String { rawValue }
    var title: String {
        switch self {
        case .hide: return "Hide them"
        case .quit: return "Quit them"
        }
    }
}

/// A rectangle as fractions (0…1) of the screen's visible area, origin at its top-left, y down.
struct UnitRect: Codable, Hashable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

/// One window of a setup: a browser window with one or more websites, or an app (optionally opened on a folder).
struct SetupSlot: Codable, Hashable, Identifiable {
    enum Kind: String, Codable { case website, app }

    var id: UUID
    var kind: Kind
    /// Website windows: the first URL is the page shown, the others open as extra tabs.
    var urls: [String]
    /// App windows: the app to open.
    var app: AllowedApp?
    /// App windows: a folder (or file) path the app opens, e.g. a project folder for an editor.
    var folder: String?
    /// Custom layouts only: where the window goes.
    var frame: UnitRect?

    init(id: UUID = UUID(), kind: Kind = .website, urls: [String] = [], app: AllowedApp? = nil,
         folder: String? = nil, frame: UnitRect? = nil) {
        self.id = id
        self.kind = kind
        self.urls = urls
        self.app = app
        self.folder = folder
        self.frame = frame
    }

    static func website(_ urls: [String], frame: UnitRect? = nil) -> SetupSlot {
        SetupSlot(kind: .website, urls: urls, frame: frame)
    }

    static func app(_ app: AllowedApp, folder: String? = nil, frame: UnitRect? = nil) -> SetupSlot {
        SetupSlot(kind: .app, app: app, folder: folder, frame: frame)
    }
}

/// Something the user locks in on, e.g. "CS128": its windows (websites and apps), layout, browser and allowlists.
struct Subject: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var preset: LayoutPreset
    /// Every website of the setup as full URLs (the study sites: never judged or closed). Kept in sync with
    /// the website slots by `SubjectValidator.subject(…)`.
    var sites: [String]
    var allowedApps: [AllowedApp]
    var extraDomains: [String]
    var createdAt: Date
    /// The setup's windows. With a preset, one per zone (left to right); with a custom layout, each has a frame.
    var slots: [SetupSlot]
    /// True when `slots` carry their own frames (captured from the screen) instead of following `preset`.
    var usesCustomLayout: Bool
    var browser: Browser
    var unusedApps: UnusedAppsAction

    init(id: UUID = UUID(), name: String, preset: LayoutPreset = .split, sites: [String] = [],
         allowedApps: [AllowedApp] = [], extraDomains: [String] = [], createdAt: Date = Date(),
         slots: [SetupSlot]? = nil, usesCustomLayout: Bool = false, browser: Browser = .chrome,
         unusedApps: UnusedAppsAction = .hide) {
        self.id = id
        self.name = name
        self.preset = preset
        self.sites = sites
        self.allowedApps = allowedApps
        self.extraDomains = extraDomains
        self.createdAt = createdAt
        self.slots = slots ?? sites.map { SetupSlot.website([$0]) }
        self.usesCustomLayout = usesCustomLayout
        self.browser = browser
        self.unusedApps = unusedApps
    }

    /// The apps the setup opens in its windows.
    var slotApps: [AllowedApp] { slots.filter { $0.kind == .app }.compactMap(\.app) }
}

extension Subject {
    /// Setups saved before slots, browsers and the unused-apps choice existed get one website slot per site,
    /// Chrome, and hidden (not quit) unused apps.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let sites = try container.decode([String].self, forKey: .sites)
        self.init(id: try container.decode(UUID.self, forKey: .id),
                  name: try container.decode(String.self, forKey: .name),
                  preset: try container.decode(LayoutPreset.self, forKey: .preset),
                  sites: sites,
                  allowedApps: try container.decode([AllowedApp].self, forKey: .allowedApps),
                  extraDomains: try container.decode([String].self, forKey: .extraDomains),
                  createdAt: try container.decode(Date.self, forKey: .createdAt),
                  slots: try container.decodeIfPresent([SetupSlot].self, forKey: .slots),
                  usesCustomLayout: try container.decodeIfPresent(Bool.self, forKey: .usesCustomLayout) ?? false,
                  browser: try container.decodeIfPresent(Browser.self, forKey: .browser) ?? .chrome,
                  unusedApps: try container.decodeIfPresent(UnusedAppsAction.self, forKey: .unusedApps) ?? .hide)
    }
}
