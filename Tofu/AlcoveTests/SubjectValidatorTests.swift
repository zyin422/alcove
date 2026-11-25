import XCTest
@testable import Alcove

final class SubjectValidatorTests: XCTestCase {
    // MARK: errors(name:sites:preset:)

    func testValidSplitSubjectHasNoErrors() {
        let errors = SubjectValidator.errors(name: "CS128", sites: ["https://cs128.org", "Piazza.com/class/x"],
                                             preset: .split)
        XCTAssertEqual(errors, [])
    }

    func testValidSingleSiteLayouts() {
        XCTAssertEqual(SubjectValidator.errors(name: "MATH241", sites: ["desmos.com"], preset: .full), [])
        XCTAssertEqual(SubjectValidator.errors(name: "MATH241", sites: ["desmos.com"], preset: .mainSide), [])
    }

    func testBlankNameIsRequired() {
        XCTAssertEqual(SubjectValidator.errors(name: "", sites: ["cs128.org"], preset: .full),
                       ["Name is required"])
        XCTAssertEqual(SubjectValidator.errors(name: "  \n", sites: ["cs128.org"], preset: .full),
                       ["Name is required"])
    }

    func testMissingSitesAskForThePresetCount() {
        XCTAssertEqual(SubjectValidator.errors(name: "CS128", sites: ["cs128.org", "  "], preset: .split),
                       ["Add 2 sites for this layout"])
        XCTAssertEqual(SubjectValidator.errors(name: "CS128", sites: [], preset: .thirds),
                       ["Add 2 sites for this layout"])
        XCTAssertEqual(SubjectValidator.errors(name: "CS128", sites: [""], preset: .full),
                       ["Add 1 site for this layout"])
    }

    func testTooManySitesAskForThePresetCount() {
        XCTAssertEqual(SubjectValidator.errors(name: "CS128", sites: ["a.com", "b.com"], preset: .full),
                       ["Add 1 site for this layout"])
    }

    func testInvalidSiteIsReportedByPosition() {
        XCTAssertEqual(SubjectValidator.errors(name: "CS128", sites: ["cs128.org", "not a url"], preset: .split),
                       ["Site 2 is not a valid URL"])
        XCTAssertEqual(SubjectValidator.errors(name: "CS128", sites: ["https://"], preset: .full),
                       ["Site 1 is not a valid URL"])
    }

    func testErrorsComeInDisplayOrder() {
        XCTAssertEqual(SubjectValidator.errors(name: " ", sites: ["%%%", ""], preset: .split),
                       ["Name is required", "Add 2 sites for this layout", "Site 1 is not a valid URL"])
    }

    // MARK: Helpers used when saving

    func testSitesForSaveAddsSchemeAndKeepsOnlyThePresetCount() {
        XCTAssertEqual(SubjectValidator.sitesForSave(["cs128.org", " https://prairielearn.org/pl "], preset: .split),
                       ["https://cs128.org", "https://prairielearn.org/pl"])
        XCTAssertEqual(SubjectValidator.sitesForSave(["cs128.org", "piazza.com"], preset: .full),
                       ["https://cs128.org"])
    }

    func testSiteSlotsAlwaysHaveAtLeastTwoEntries() {
        XCTAssertEqual(SubjectValidator.siteSlots([]), ["", ""])
        XCTAssertEqual(SubjectValidator.siteSlots(["https://a.com"]), ["https://a.com", ""])
        XCTAssertEqual(SubjectValidator.siteSlots(["https://a.com", "https://b.com"]), ["https://a.com", "https://b.com"])
    }

    func testParseDomainsNormalizesSplitsAndDeduplicates() {
        XCTAssertEqual(SubjectValidator.parseDomains("Piazza.com, https://www.stackoverflow.com/questions  docs.python.org,,piazza.com"),
                       ["piazza.com", "stackoverflow.com", "docs.python.org"])
        XCTAssertEqual(SubjectValidator.parseDomains(""), [])
        XCTAssertEqual(SubjectValidator.parseDomains(" ,  %%% "), [])
    }

    func testParseDomainsFiltersOutDistractionDomains() {
        let input = "piazza.com, discord.com, reddit.com, stackoverflow.com, https://youtube.com/watch"
        let parsed = SubjectValidator.parseDomains(input)
        XCTAssertTrue(parsed.contains("piazza.com"))
        XCTAssertTrue(parsed.contains("stackoverflow.com"))
        XCTAssertTrue(parsed.contains("youtube.com"), "video allowed in extra domains for lecture clips")
        XCTAssertFalse(parsed.contains("discord.com"))
        XCTAssertFalse(parsed.contains("reddit.com"))
    }

    func testDistractionSitesAreReportedInErrors() {
        let errors = SubjectValidator.errors(name: "Test", sites: ["https://reddit.com"], preset: .full)
        XCTAssertEqual(errors, ["Site 1 cannot be a distraction site (reddit.com)"])

        let discordErrors = SubjectValidator.errors(name: "Test", sites: ["discord.com"], preset: .full)
        XCTAssertEqual(discordErrors, ["Site 1 cannot be a distraction site (discord.com)"])
    }

    func testWindowSlotsRejectsDistractionAppsAndBrowsers() {
        let safari = SetupSlot.app(AllowedApp(bundleID: "com.apple.Safari", name: "Safari"))
        let errors = SubjectValidator.errors(name: "Test", slots: [safari], customLayout: false)
        XCTAssertTrue(errors.contains("Window 1 cannot use Safari: prohibited distraction app or unmonitored browser"))

        let discord = SetupSlot.app(AllowedApp(bundleID: "com.hnc.Discord", name: "Discord"))
        let discordErrors = SubjectValidator.errors(name: "Test", slots: [discord], customLayout: false)
        XCTAssertTrue(discordErrors.contains("Window 1 cannot use Discord: prohibited distraction app or unmonitored browser"))
    }

    func testWindowSlotsRejectsDistractionWebsites() {
        let redditSlot = SetupSlot.website(["https://reddit.com/r/all"])
        let errors = SubjectValidator.errors(name: "Test", slots: [redditSlot], customLayout: false)
        XCTAssertTrue(errors.contains("Window 1 website cannot be a distraction site (reddit.com)"))
    }
}
