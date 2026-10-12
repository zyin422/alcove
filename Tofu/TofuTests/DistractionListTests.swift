import XCTest
@testable import Tofu

final class DistractionListTests: XCTestCase {
    func testEachCategoryHasItsSites() {
        XCTAssertEqual(DistractionList.category(of: "mail.google.com"), .messaging)
        XCTAssertEqual(DistractionList.category(of: "outlook.office.com"), .messaging)
        XCTAssertEqual(DistractionList.category(of: "www.instagram.com"), .social)
        XCTAssertEqual(DistractionList.category(of: "www.netflix.com"), .streaming)
        XCTAssertEqual(DistractionList.category(of: "m.youtube.com"), .video)
        XCTAssertEqual(DistractionList.category(of: "www.amazon.com"), .shopping)
    }

    func testWorkSitesAndLookalikesAreNotDistractions() {
        XCTAssertNil(DistractionList.category(of: "aws.amazon.com"))
        XCTAssertNil(DistractionList.category(of: "docs.google.com"))
        XCTAssertNil(DistractionList.category(of: "notyoutube.com"))
        XCTAssertNil(DistractionList.category(of: ""))
    }

    func testHostsListsEveryCategoryWithoutDuplicates() {
        let hosts = DistractionList.hosts
        XCTAssertEqual(Set(hosts).count, hosts.count)
        for category in DistractionList.Category.allCases {
            XCTAssertFalse(DistractionList.domains[category]?.isEmpty ?? true, category.rawValue)
        }
    }
}
