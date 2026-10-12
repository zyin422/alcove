import XCTest
@testable import Tofu

/// Uses made-up values only ("abc.def"); the real .env is never read here.
final class EnvFileTests: XCTestCase {
    // MARK: parse

    func testParsesKeyValueLines() {
        let parsed = EnvFile.parse("DISCORD_BOT_TOKEN=abc.def\nOTHER=1")
        XCTAssertEqual(parsed, ["DISCORD_BOT_TOKEN": "abc.def", "OTHER": "1"])
    }

    func testEmptyTextGivesNoValues() {
        XCTAssertEqual(EnvFile.parse(""), [:])
        XCTAssertEqual(EnvFile.parse("\n\n   \n"), [:])
    }

    func testIgnoresBlankLinesAndComments() {
        let text = """
        # team bot
        KEY=abc.def

           # indented comment
        #COMMENTED=1
        """
        XCTAssertEqual(EnvFile.parse(text), ["KEY": "abc.def"])
    }

    func testTrimsWhitespaceAroundKeyAndValue() {
        XCTAssertEqual(EnvFile.parse("  KEY =  abc.def \t\n\tOTHER=x  "), ["KEY": "abc.def", "OTHER": "x"])
    }

    func testSupportsExportPrefix() {
        let parsed = EnvFile.parse("export KEY=abc.def\nexport   SPACED = 1")
        XCTAssertEqual(parsed, ["KEY": "abc.def", "SPACED": "1"])
    }

    func testOnlyAWholeExportWordIsAPrefix() {
        XCTAssertEqual(EnvFile.parse("exported=1"), ["exported": "1"])
    }

    func testStripsOnePairOfMatchingQuotes() {
        let parsed = EnvFile.parse("A=\"abc.def\"\nB='abc.def'\nC=\"\"abc.def\"\"")
        XCTAssertEqual(parsed["A"], "abc.def")
        XCTAssertEqual(parsed["B"], "abc.def")
        XCTAssertEqual(parsed["C"], "\"abc.def\"")   // only one pair is removed
    }

    func testKeepsUnpairedOrMismatchedQuotes() {
        let parsed = EnvFile.parse("A=\"abc\nB=abc'\nC=\"abc'\nD=\"")
        XCTAssertEqual(parsed["A"], "\"abc")
        XCTAssertEqual(parsed["B"], "abc'")
        XCTAssertEqual(parsed["C"], "\"abc'")
        XCTAssertEqual(parsed["D"], "\"")
    }

    func testQuotedValueKeepsItsInnerText() {
        XCTAssertEqual(EnvFile.parse("KEY=\"  a b # c  \"")["KEY"], "  a b # c  ")
    }

    func testFirstEqualsSplitsKeyFromValue() {
        XCTAssertEqual(EnvFile.parse("KEY=abc==def=")["KEY"], "abc==def=")
    }

    func testLaterDuplicatesWin() {
        XCTAssertEqual(EnvFile.parse("KEY=first\nOTHER=1\nKEY=second")["KEY"], "second")
    }

    func testEmptyValueIsKeptAsEmpty() {
        XCTAssertEqual(EnvFile.parse("KEY=\nQUOTED=\"\""), ["KEY": "", "QUOTED": ""])
    }

    func testIgnoresLinesWithoutKeyOrEquals() {
        XCTAssertEqual(EnvFile.parse("just text\n=nokey\n  =alsonokey\nKEY=abc.def"), ["KEY": "abc.def"])
    }

    func testHandlesWindowsLineEndings() {
        XCTAssertEqual(EnvFile.parse("A=abc.def\r\nB=1\r\n"), ["A": "abc.def", "B": "1"])
    }

    func testIgnoresLeadingByteOrderMark() {
        XCTAssertEqual(EnvFile.parse("\u{FEFF}KEY=abc.def"), ["KEY": "abc.def"])
    }

    // MARK: bundledValue

    /// A throwaway bundle whose Resources folder holds `discord.env` (nothing when `contents` is nil).
    private func makeBundle(discordEnv contents: String?) throws -> Bundle {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("EnvFileTests-\(UUID().uuidString)", isDirectory: true)
        let resources = root.appendingPathComponent("Fake.bundle/Contents/Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        if let contents {
            try contents.write(to: resources.appendingPathComponent("discord.env"), atomically: true, encoding: .utf8)
        }
        return try XCTUnwrap(Bundle(url: root.appendingPathComponent("Fake.bundle")))
    }

    func testBundledValueReadsDiscordEnvFromTheBundle() throws {
        let bundle = try makeBundle(discordEnv: "# team\nDISCORD_BOT_TOKEN=abc.def\nOTHER=1\n")
        XCTAssertEqual(EnvFile.bundledValue("DISCORD_BOT_TOKEN", bundle: bundle), "abc.def")
        XCTAssertEqual(EnvFile.bundledValue("OTHER", bundle: bundle), "1")
    }

    func testBundledValueIsNilForAnUnknownKey() throws {
        let bundle = try makeBundle(discordEnv: "OTHER=1\n")
        XCTAssertNil(EnvFile.bundledValue("DISCORD_BOT_TOKEN", bundle: bundle))
    }

    func testBundledValueIsNilWhenTheValueIsEmpty() throws {
        let bundle = try makeBundle(discordEnv: "DISCORD_BOT_TOKEN=\n")
        XCTAssertNil(EnvFile.bundledValue("DISCORD_BOT_TOKEN", bundle: bundle))
        let blank = try makeBundle(discordEnv: "DISCORD_BOT_TOKEN=\"  \"\n")
        XCTAssertNil(EnvFile.bundledValue("DISCORD_BOT_TOKEN", bundle: blank))
    }

    func testBundledValueIsNilWhenTheFileIsMissing() throws {
        let bundle = try makeBundle(discordEnv: nil)
        XCTAssertNil(EnvFile.bundledValue("DISCORD_BOT_TOKEN", bundle: bundle))
    }
}
