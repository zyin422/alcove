import XCTest
@testable import Tofu

final class AppCatalogTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppCatalogTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// Writes `<directory>/<path>/Contents/Info.plist` with the given keys and returns the bundle URL.
    @discardableResult
    private func makeApp(_ path: String, in directory: URL, info: [String: String]) throws -> URL {
        let bundleURL = directory.appendingPathComponent(path, isDirectory: true)
        let contents = bundleURL.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try plist.write(to: contents.appendingPathComponent("Info.plist"))
        return bundleURL
    }

    func testScanReadsTopLevelAndOneSubfolderLevelSortedByName() throws {
        let apps = root.appendingPathComponent("Applications", isDirectory: true)
        try makeApp("Zeta.app", in: apps, info: ["CFBundleIdentifier": "com.test.zeta", "CFBundleName": "Zeta"])
        try makeApp("alpha.app", in: apps, info: ["CFBundleIdentifier": "com.test.alpha",
                                                  "CFBundleName": "alpha", "CFBundleDisplayName": "alpha Display"])
        try makeApp("Utilities/Beta.app", in: apps, info: ["CFBundleIdentifier": "com.test.beta", "CFBundleName": "Beta"])
        try makeApp("Nested/Deeper/Gamma.app", in: apps, info: ["CFBundleIdentifier": "com.test.gamma"])
        try Data("not an app".utf8).write(to: apps.appendingPathComponent("notes.txt"))

        let found = AppCatalog.scan(directories: [apps])

        XCTAssertEqual(found, [
            AllowedApp(bundleID: "com.test.alpha", name: "alpha Display"),
            AllowedApp(bundleID: "com.test.beta", name: "Beta"),
            AllowedApp(bundleID: "com.test.zeta", name: "Zeta"),
        ])
    }

    func testBundleWithoutIdentifierIsSkippedAndFileNameIsTheFallbackName() throws {
        let apps = root.appendingPathComponent("Applications", isDirectory: true)
        try makeApp("NoID.app", in: apps, info: ["CFBundleName": "No ID"])
        try makeApp("Plain.app", in: apps, info: ["CFBundleIdentifier": "com.test.plain"])

        XCTAssertEqual(AppCatalog.scan(directories: [apps]), [AllowedApp(bundleID: "com.test.plain", name: "Plain")])
    }

    func testDuplicateBundleIDKeepsTheFirstDirectoryAndMissingDirectoriesAreIgnored() throws {
        let first = root.appendingPathComponent("First", isDirectory: true)
        let second = root.appendingPathComponent("Second", isDirectory: true)
        try makeApp("Notes.app", in: first, info: ["CFBundleIdentifier": "com.test.notes", "CFBundleName": "Notes"])
        try makeApp("Notes Copy.app", in: second, info: ["CFBundleIdentifier": "com.test.notes", "CFBundleName": "Notes Copy"])
        try makeApp("Calendar.app", in: second, info: ["CFBundleIdentifier": "com.test.calendar", "CFBundleName": "Calendar"])
        let missing = root.appendingPathComponent("DoesNotExist", isDirectory: true)

        let found = AppCatalog.scan(directories: [missing, first, second])

        XCTAssertEqual(found, [
            AllowedApp(bundleID: "com.test.calendar", name: "Calendar"),
            AllowedApp(bundleID: "com.test.notes", name: "Notes"),
        ])
    }

    func testDefaultDirectories() {
        let paths = AppCatalog.defaultDirectories().map(\.path)
        XCTAssertEqual(Array(paths.prefix(2)), ["/Applications", "/System/Applications"])
        XCTAssertTrue(paths[2].hasSuffix("/Applications"))
        XCTAssertEqual(paths.count, 3)
    }

    func testFilterDropsExcludedAppsAndMatchesQueryCaseInsensitively() {
        let apps = [
            AllowedApp(bundleID: "com.google.Chrome", name: "Google Chrome"),
            AllowedApp(bundleID: "com.apple.Notes", name: "Notes"),
            AllowedApp(bundleID: "com.microsoft.VSCode", name: "Visual Studio Code"),
        ]
        let excluded: Set<String> = ["com.google.Chrome", "com.apple.finder"]

        XCTAssertEqual(AppCatalog.filter(apps, query: "", excluding: excluded).map(\.name),
                       ["Notes", "Visual Studio Code"])
        XCTAssertEqual(AppCatalog.filter(apps, query: " studio ", excluding: excluded).map(\.name),
                       ["Visual Studio Code"])
        XCTAssertEqual(AppCatalog.filter(apps, query: "chrome", excluding: excluded), [])
    }
}
