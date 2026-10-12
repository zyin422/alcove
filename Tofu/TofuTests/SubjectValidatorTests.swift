import XCTest
@testable import Tofu

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
}
