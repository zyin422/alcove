import XCTest
@testable import Tofu

final class SettingsStatusTests: XCTestCase {
    private let bot = DiscordUser(id: "42", username: "lockbot")

    // MARK: - Discord test connection

    func testDiscordSuccessShowsUsernameAndServerCount() {
        XCTAssertEqual(SettingsStatus.discordResult(.success((user: bot, guildCount: 3))),
                       "Connected as lockbot · 3 servers")
    }

    func testDiscordSuccessWithOneServerIsSingular() {
        XCTAssertEqual(SettingsStatus.discordResult(.success((user: bot, guildCount: 1))),
                       "Connected as lockbot · 1 server")
    }

    func testDiscordSuccessWithNoServersAsksForAnInvite() {
        XCTAssertEqual(SettingsStatus.discordResult(.success((user: bot, guildCount: 0))),
                       "Connected as lockbot · 0 servers — invite the bot to a server")
    }

    func testDiscordHTTP401PointsAtTheToken() {
        XCTAssertEqual(SettingsStatus.discordResult(.failure(DiscordError.http(401))),
                       "Failed: HTTP 401 — the bot token is invalid")
    }

    func testDiscordOtherHTTPStatusShowsTheCode() {
        XCTAssertEqual(SettingsStatus.discordResult(.failure(DiscordError.http(403))), "Failed: HTTP 403")
        XCTAssertEqual(SettingsStatus.discordResult(.failure(DiscordError.http(500))), "Failed: HTTP 500")
    }

    func testDiscordTransportErrorShowsTheMessage() {
        let error = DiscordError.transport("The Internet connection appears to be offline.")
        XCTAssertEqual(SettingsStatus.discordResult(.failure(error)),
                       "Failed: network error (The Internet connection appears to be offline.)")
    }

    func testDiscordDecodingError() {
        XCTAssertEqual(SettingsStatus.discordResult(.failure(DiscordError.decoding)),
                       "Failed: unexpected response from Discord")
    }

    func testNonDiscordErrorUsesItsLocalizedDescription() {
        let error = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "boom"])
        XCTAssertEqual(SettingsStatus.discordResult(.failure(error)), "Failed: boom")
    }

    // MARK: - Chrome request access

    func testChromeAllowedWhenThereIsNoError() {
        XCTAssertEqual(SettingsStatus.chromeResult(nil), "Chrome control allowed")
    }

    func testChromeResultForEachError() {
        XCTAssertEqual(SettingsStatus.chromeResult(.notInstalled), "Google Chrome not installed")
        XCTAssertEqual(SettingsStatus.chromeResult(.automationDenied),
                       "Denied — enable in System Settings › Privacy & Security › Automation")
        XCTAssertEqual(SettingsStatus.chromeResult(.profileNotReady),
                       "Chrome is still starting — try again in a moment")
        XCTAssertEqual(SettingsStatus.chromeResult(.scriptFailed("Syntax error")),
                       "Chrome script failed: Syntax error")
    }

    // MARK: - Invite URL

    func testInviteURLForNumericApplicationID() {
        XCTAssertEqual(SettingsStatus.inviteURL(appID: "123")?.absoluteString,
                       "https://discord.com/oauth2/authorize?client_id=123&scope=bot&permissions=3072")
        XCTAssertEqual(SettingsStatus.inviteURL(appID: "  1234567890123456789\n")?.absoluteString,
                       "https://discord.com/oauth2/authorize?client_id=1234567890123456789&scope=bot&permissions=3072")
    }

    func testInviteURLIsNilForEmptyOrNonNumericID() {
        XCTAssertNil(SettingsStatus.inviteURL(appID: ""))
        XCTAssertNil(SettingsStatus.inviteURL(appID: "   "))
        XCTAssertNil(SettingsStatus.inviteURL(appID: "abc"))
        XCTAssertNil(SettingsStatus.inviteURL(appID: "12a3"))
        XCTAssertNil(SettingsStatus.inviteURL(appID: "-123"))
        XCTAssertNil(SettingsStatus.inviteURL(appID: "1 23"))
        XCTAssertNil(SettingsStatus.inviteURL(appID: "１２３"))   // full-width digits
    }

    func testInviteTemplateMatchesTheSpec() {
        XCTAssertEqual(SettingsStatus.inviteTemplate,
                       "https://discord.com/oauth2/authorize?client_id=<APP_ID>&scope=bot&permissions=3072")
    }

    // MARK: - Small texts

    func testPhrasePreviewReplacesEverySubjectPlaceholder() {
        XCTAssertEqual(SettingsStatus.phrasePreview(template: "I give up on {subject}"), "I give up on CS128")
        XCTAssertEqual(SettingsStatus.phrasePreview(template: "{subject} beat me, bye {subject}", subject: "MATH241"),
                       "MATH241 beat me, bye MATH241")
        XCTAssertEqual(SettingsStatus.phrasePreview(template: "I quit"), "I quit")
    }

    func testDemoSummary() {
        XCTAssertEqual(SettingsStatus.demoSummary(count: 0), "No demo data loaded")
        XCTAssertEqual(SettingsStatus.demoSummary(count: 1), "1 demo session loaded")
        XCTAssertEqual(SettingsStatus.demoSummary(count: 43), "43 demo sessions loaded")
    }

    func testCleanedTokenTrimsWhitespaceAndBotPrefix() {
        XCTAssertEqual(SettingsStatus.cleanedToken("  abc.def.ghi \n"), "abc.def.ghi")
        XCTAssertEqual(SettingsStatus.cleanedToken("Bot abc.def.ghi"), "abc.def.ghi")
        XCTAssertEqual(SettingsStatus.cleanedToken(" Bot   abc.def.ghi "), "abc.def.ghi")
        XCTAssertNil(SettingsStatus.cleanedToken(""))
        XCTAssertNil(SettingsStatus.cleanedToken("  \n "))
    }
}
