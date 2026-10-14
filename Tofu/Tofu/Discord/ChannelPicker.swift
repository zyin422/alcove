import Foundation

/// One entry of `GET /guilds/{id}/channels`. Unknown JSON fields are ignored.
struct DiscordChannel: Decodable, Equatable {
    let id: String
    let name: String?
    let type: Int       // 0 = guild text; 2 = voice; 4 = category; others ignored
    let position: Int?
}

/// Chooses which channels of a guild to try when posting (spec §9).
enum ChannelPicker {
    static let preferredNames = ["lock-in", "locked-in", "lockin", "accountability"]

    /// Text channels only (type == 0). Order: preferred names in list order, then the cached id (if it is still
    /// a text channel), then remaining text channels by position (nil last), ties by id. No duplicates.
    /// A named channel such as #locked-in wins over a cache that still points at #general.
    static func candidates(from channels: [DiscordChannel], cachedID: String?) -> [String] {
        let textChannels = channels.filter { $0.type == 0 }.sorted(by: positionOrder)
        var result: [String] = []
        var seen = Set<String>()
        func add(_ id: String) {
            if seen.insert(id).inserted { result.append(id) }
        }

        for preferred in preferredNames {
            for channel in textChannels where channel.name?.lowercased() == preferred {
                add(channel.id)
            }
        }
        if let cachedID, textChannels.contains(where: { $0.id == cachedID }) {
            add(cachedID)
        }
        for channel in textChannels {
            add(channel.id)
        }
        return result
    }

    /// Position ascending with nil last; ties broken by snowflake id (numeric order).
    private static func positionOrder(_ a: DiscordChannel, _ b: DiscordChannel) -> Bool {
        switch (a.position, b.position) {
        case let (pa?, pb?) where pa != pb:
            return pa < pb
        case (.some, nil):
            return true
        case (nil, .some):
            return false
        default:
            return idOrder(a.id, b.id)
        }
    }

    /// Snowflakes are decimal strings without leading zeros, so shorter means smaller.
    private static func idOrder(_ a: String, _ b: String) -> Bool {
        a.count != b.count ? a.count < b.count : a < b
    }
}
