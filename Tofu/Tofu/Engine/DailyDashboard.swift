import Foundation
import SQLite3

/// Weather and commute condition summary loaded from the local ai-digest cache.
public struct WeatherBriefing: Codable, Equatable {
    public let location: String
    public let tempF: Double
    public let feelsLikeF: Double?
    public let highF: Double?
    public let lowF: Double?
    public let condition: String
    public let icon: String
    public let advisory: String?

    enum CodingKeys: String, CodingKey {
        case location
        case tempF = "temp_f"
        case feelsLikeF = "feels_like_f"
        case highF = "high_f"
        case lowF = "low_f"
        case condition
        case icon
        case advisory
    }

    public init(location: String, tempF: Double, feelsLikeF: Double? = nil,
                highF: Double? = nil, lowF: Double? = nil, condition: String,
                icon: String, advisory: String? = nil) {
        self.location = location
        self.tempF = tempF
        self.feelsLikeF = feelsLikeF
        self.highF = highF
        self.lowF = lowF
        self.condition = condition
        self.icon = icon
        self.advisory = advisory
    }
}

/// A top-ranked research paper or technical article from the local ai-digest pipeline.
public struct DigestFeedItem: Identifiable, Codable, Equatable {
    public let id: String
    public let title: String
    public let source: String
    public let score: Int
    public let readTimeMin: Double
    public let url: String

    public init(id: String, title: String, source: String, score: Int, readTimeMin: Double, url: String) {
        self.id = id
        self.title = title
        self.source = source
        self.score = score
        self.readTimeMin = readTimeMin
        self.url = url
    }
}

/// Reads local start-of-day telemetry and AI feed summaries from the unified dashboard pipeline.
public enum DailyDashboardReader {
    public static var digestDataDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("ai-digest/data")
    }

    public static func loadWeather() -> WeatherBriefing? {
        let weatherURL = digestDataDirectory.appendingPathComponent("weather_cache.json")
        guard let data = try? Data(contentsOf: weatherURL) else { return nil }
        return try? JSONDecoder().decode(WeatherBriefing.self, from: data)
    }

    public static func loadTopDigestItems(limit: Int = 3) -> [DigestFeedItem] {
        let dbURL = digestDataDirectory.appendingPathComponent("digest.db")
        guard FileManager.default.fileExists(atPath: dbURL.path) else { return [] }

        var db: OpaquePointer?
        guard sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_close(db) }

        let query = "SELECT id, title, source, score, read_time_min, url FROM items ORDER BY date DESC, score DESC LIMIT ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int(stmt, 1, Int32(limit))

        var items: [DigestFeedItem] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = String(cString: sqlite3_column_text(stmt, 0))
            let title = String(cString: sqlite3_column_text(stmt, 1))
            let source = String(cString: sqlite3_column_text(stmt, 2))
            let score = Int(sqlite3_column_int(stmt, 3))
            let readTime = sqlite3_column_double(stmt, 4)
            let url = String(cString: sqlite3_column_text(stmt, 5))

            items.append(DigestFeedItem(id: id, title: title, source: source,
                                        score: score, readTimeMin: readTime, url: url))
        }
        return items
    }
}
