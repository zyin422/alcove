import Foundation

/// How the screen is split between Chrome study windows and our app while locked in.
enum LayoutPreset: String, Codable, CaseIterable, Identifiable {
    case split      // Chrome | Chrome (2 sites) + mini timer
    case full       // Chrome (1 site) + mini timer
    case thirds     // App | Chrome | Chrome (2 sites)
    case mainSide   // Chrome 70% | App 30% (1 site)

    var id: String { rawValue }
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

/// Something the user locks in on, e.g. "CS128", with its sites, layout and allowlists.
struct Subject: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var preset: LayoutPreset
    var sites: [String]
    var allowedApps: [AllowedApp]
    var extraDomains: [String]
    var createdAt: Date

    init(id: UUID = UUID(), name: String, preset: LayoutPreset = .split, sites: [String] = [],
         allowedApps: [AllowedApp] = [], extraDomains: [String] = [], createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.preset = preset
        self.sites = sites
        self.allowedApps = allowedApps
        self.extraDomains = extraDomains
        self.createdAt = createdAt
    }
}
