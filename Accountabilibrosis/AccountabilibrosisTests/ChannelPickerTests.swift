import XCTest
@testable import Accountabilibrosis

final class ChannelPickerTests: XCTestCase {
    private func text(_ id: String, _ name: String, _ position: Int?) -> DiscordChannel {
        DiscordChannel(id: id, name: name, type: 0, position: position)
    }

    func testCachedChannelFirstWhenPresentAndText() {
        let channels = [text("10", "general", 0), text("11", "random", 1), text("12", "lock-in", 2)]
        XCTAssertEqual(ChannelPicker.candidates(from: channels, cachedID: "11"), ["11", "12", "10"])
    }

    func testCachedChannelIgnoredWhenMissing() {
        let channels = [text("10", "general", 0), text("12", "lock-in", 2)]
        XCTAssertEqual(ChannelPicker.candidates(from: channels, cachedID: "99"), ["12", "10"])
    }

    func testCachedChannelIgnoredWhenVoice() {
        let channels = [text("10", "general", 0), DiscordChannel(id: "20", name: "Study Room", type: 2, position: 0)]
        XCTAssertEqual(ChannelPicker.candidates(from: channels, cachedID: "20"), ["10"])
    }

    func testPreferredNamesInListOrder() {
        let channels = [
            text("1", "accountability", 0),
            text("2", "general", 1),
            text("3", "lockin", 2),
            text("4", "lock-in", 3),
            text("5", "locked-in", 4),
        ]
        XCTAssertEqual(ChannelPicker.candidates(from: channels, cachedID: nil), ["4", "5", "3", "1", "2"])
    }

    func testPreferredNameMatchIgnoresCase() {
        let channels = [text("1", "general", 0), text("2", "Lock-In", 1)]
        XCTAssertEqual(ChannelPicker.candidates(from: channels, cachedID: nil), ["2", "1"])
    }

    func testRemainingByPositionWithNilLast() {
        let channels = [text("1", "c", 3), text("2", "no-position", nil), text("3", "a", 1), text("4", "b", 2)]
        XCTAssertEqual(ChannelPicker.candidates(from: channels, cachedID: nil), ["3", "4", "1", "2"])
    }

    func testPositionTiesBrokenByNumericID() {
        let channels = [text("100", "x", 1), text("99", "y", 1), text("5", "z", nil), text("40", "w", nil)]
        XCTAssertEqual(ChannelPicker.candidates(from: channels, cachedID: nil), ["99", "100", "5", "40"])
    }

    func testVoiceAndCategoryExcluded() {
        let channels = [
            DiscordChannel(id: "1", name: "Voice", type: 2, position: 0),
            DiscordChannel(id: "2", name: "TEXT CHANNELS", type: 4, position: 0),
            DiscordChannel(id: "3", name: "lock-in", type: 2, position: 1),
            text("4", "general", 5),
        ]
        XCTAssertEqual(ChannelPicker.candidates(from: channels, cachedID: nil), ["4"])
    }

    func testNoDuplicatesWhenCachedIsAlsoPreferred() {
        let channels = [text("1", "general", 0), text("2", "lock-in", 1)]
        let result = ChannelPicker.candidates(from: channels, cachedID: "2")
        XCTAssertEqual(result, ["2", "1"])
        XCTAssertEqual(Set(result).count, result.count)
    }

    func testEmptyInputGivesNoCandidates() {
        XCTAssertEqual(ChannelPicker.candidates(from: [], cachedID: "1"), [])
    }

    func testDecodesDiscordChannelJSON() throws {
        let json = """
        [
          {"id": "10", "type": 0, "guild_id": "1", "position": 2, "name": "general", "nsfw": false},
          {"id": "11", "type": 4, "guild_id": "1", "position": 0, "name": "Text Channels"},
          {"id": "12", "type": 0, "guild_id": "1"}
        ]
        """
        let channels = try JSONDecoder().decode([DiscordChannel].self, from: Data(json.utf8))
        XCTAssertEqual(channels, [
            DiscordChannel(id: "10", name: "general", type: 0, position: 2),
            DiscordChannel(id: "11", name: "Text Channels", type: 4, position: 0),
            DiscordChannel(id: "12", name: nil, type: 0, position: nil),
        ])
    }
}
