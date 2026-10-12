import XCTest
@testable import Tofu

/// Uses a dedicated test service so the real Discord token is never touched.
final class KeychainTests: XCTestCase {
    private let service = "com.tofu.tests"
    private var account = ""

    override func setUp() {
        super.setUp()
        account = "test-\(UUID().uuidString)"
    }

    override func tearDown() {
        Keychain.delete(service: service, account: account)
        super.tearDown()
    }

    func testSecretsCoordinates() {
        XCTAssertEqual(Secrets.discordService, "com.tofu.discord")
        XCTAssertEqual(Secrets.discordAccount, "bot-token")
    }

    func testMissingItemReturnsNil() {
        XCTAssertNil(Keychain.get(service: service, account: account))
    }

    func testSetThenGet() {
        XCTAssertTrue(Keychain.set("token-1", service: service, account: account))
        XCTAssertEqual(Keychain.get(service: service, account: account), "token-1")
    }

    func testSetOverwritesExistingValue() {
        XCTAssertTrue(Keychain.set("token-1", service: service, account: account))
        XCTAssertTrue(Keychain.set("token-2", service: service, account: account))
        XCTAssertEqual(Keychain.get(service: service, account: account), "token-2")
    }

    func testDeleteRemovesItemAndIsSafeWhenMissing() {
        Keychain.set("token-1", service: service, account: account)
        Keychain.delete(service: service, account: account)
        XCTAssertNil(Keychain.get(service: service, account: account))
        Keychain.delete(service: service, account: account)
        XCTAssertNil(Keychain.get(service: service, account: account))
    }
}
