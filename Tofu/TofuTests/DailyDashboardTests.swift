import XCTest
@testable import Tofu

final class DailyDashboardTests: XCTestCase {
    func testWeatherBriefingDecoding() throws {
        let json = """
        {
          "location": "Urbana, IL (UIUC Campus)",
          "temp_f": 25.3,
          "feels_like_f": 17.3,
          "high_f": 42.2,
          "low_f": 24.6,
          "condition": "Clear",
          "icon": "☀️",
          "advisory": "Freezing — coat required."
        }
        """.data(using: .utf8)!

        let weather = try JSONDecoder().decode(WeatherBriefing.self, from: json)
        XCTAssertEqual(weather.location, "Urbana, IL (UIUC Campus)")
        XCTAssertEqual(weather.tempF, 25.3)
        XCTAssertEqual(weather.condition, "Clear")
        XCTAssertEqual(weather.icon, "☀️")
        XCTAssertEqual(weather.advisory, "Freezing — coat required.")
    }

    func testDigestItemProperties() {
        let item = DigestFeedItem(id: "1", title: "Build full-stack Android apps with Gemini",
                                  source: "Google for Developers", score: 121, readTimeMin: 5.0,
                                  url: "https://developers.google.com")
        XCTAssertEqual(item.id, "1")
        XCTAssertEqual(item.score, 121)
        XCTAssertEqual(item.source, "Google for Developers")
    }

    func testDailyDashboardReaderReadsLocalDataGracefully() {
        let weather = DailyDashboardReader.loadWeather()
        // If file exists at ~/ai-digest/data/weather_cache.json, it should be loaded, else nil
        if let weather {
            XCTAssertFalse(weather.location.isEmpty)
        }
    }
}
