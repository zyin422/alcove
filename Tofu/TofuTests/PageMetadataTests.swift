import XCTest
@testable import Tofu

private struct FailingTransport: HTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        throw URLError(.timedOut)
    }
}

final class PageMetadataTests: XCTestCase {
    // MARK: - parse

    func testParsesTitleDescriptionAndSiteName() {
        let html = """
        <html><head>
        <title>CS 128 Syllabus</title>
        <meta name="description" content="Course policies and schedule">
        <meta property="og:site_name" content="CS128 @ Illinois">
        </head><body>hi</body></html>
        """
        let meta = PageMetadata.parse(html: html)
        XCTAssertEqual(meta.title, "CS 128 Syllabus")
        XCTAssertEqual(meta.description, "Course policies and schedule")
        XCTAssertEqual(meta.siteName, "CS128 @ Illinois")
    }

    func testAttributeOrderAndQuoteStyleDoNotMatter() {
        let html = """
        <meta content='Single quoted' name='description'>
        <meta content="Reversed" property="og:site_name" />
        """
        let meta = PageMetadata.parse(html: html)
        XCTAssertEqual(meta.description, "Single quoted")
        XCTAssertEqual(meta.siteName, "Reversed")
    }

    func testTagsAndAttributeNamesAreCaseInsensitive() {
        let html = #"<HTML><HEAD><TITLE>Shouting</TITLE><META NAME="Description" CONTENT="Loud"></HEAD>"#
        let meta = PageMetadata.parse(html: html)
        XCTAssertEqual(meta.title, "Shouting")
        XCTAssertEqual(meta.description, "Loud")
    }

    func testOpenGraphFallbacksAndPrecedence() {
        let onlyOG = PageMetadata.parse(html: """
        <meta property="og:title" content="OG Title"><meta property="og:description" content="OG Desc">
        """)
        XCTAssertEqual(onlyOG.title, "OG Title")
        XCTAssertEqual(onlyOG.description, "OG Desc")

        let both = PageMetadata.parse(html: """
        <title>Real</title><meta property="og:title" content="OG Title">
        <meta property="og:description" content="OG Desc"><meta name="description" content="Plain Desc">
        """)
        XCTAssertEqual(both.title, "Real")
        XCTAssertEqual(both.description, "Plain Desc")
    }

    func testDecodesEntitiesWithoutDoubleDecoding() {
        let html = """
        <title>Tom &amp; Jerry &lt;3 &gt; &quot;q&quot; it&#39;s it&#x27;s &amp;lt;</title>
        """
        XCTAssertEqual(PageMetadata.parse(html: html).title, #"Tom & Jerry <3 > "q" it's it's &lt;"#)
    }

    func testTrimsAndCollapsesWhitespace() {
        let html = "<title>\n   Hello\n\t  World  \n</title><meta name=\"description\" content=\"  a \n b  \">"
        let meta = PageMetadata.parse(html: html)
        XCTAssertEqual(meta.title, "Hello World")
        XCTAssertEqual(meta.description, "a b")
    }

    func testContentMayContainAngleBrackets() {
        let html = #"<meta name="description" content="a > b and c < d"><title>T</title>"#
        let meta = PageMetadata.parse(html: html)
        XCTAssertEqual(meta.description, "a > b and c < d")
        XCTAssertEqual(meta.title, "T")
    }

    func testEmptyValuesAreNil() {
        let meta = PageMetadata.parse(html: #"<title>  </title><meta name="description" content="">"#)
        XCTAssertNil(meta.title)
        XCTAssertNil(meta.description)
        XCTAssertNil(meta.siteName)
        let none = PageMetadata.parse(html: "just text")
        XCTAssertNil(none.title)
        XCTAssertNil(none.description)
        XCTAssertNil(none.siteName)
    }

    func testOnlyScansTheFirst200kCharacters() {
        let padding = String(repeating: "x", count: 200_000)
        XCTAssertNil(PageMetadata.parse(html: padding + "<title>Late</title>").title)
        XCTAssertEqual(PageMetadata.parse(html: "<title>Early</title>" + padding).title, "Early")
    }

    // MARK: - fetch

    private let pageHTML = Data("<title>Lecture 3</title><meta name=\"description\" content=\"Slides\">".utf8)

    func testFetchSendsBrowserLikeGetAndParses() async throws {
        let transport = MockTransport { _ in (200, self.pageHTML) }
        let meta = await PageMetadata.fetch(url: "https://cs128.org/lec3", transport: transport, timeout: 2)

        XCTAssertEqual(meta.title, "Lecture 3")
        XCTAssertEqual(meta.description, "Slides")
        XCTAssertNil(meta.siteName)
        XCTAssertEqual(transport.requests.count, 1)
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.absoluteString, "https://cs128.org/lec3")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"),
                       "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15")
        XCTAssertTrue(request.value(forHTTPHeaderField: "Accept")?.contains("text/html") == true)
        XCTAssertEqual(request.timeoutInterval, 2)
    }

    func testFetchNon2xxGivesNils() async {
        let transport = MockTransport { _ in (404, self.pageHTML) }
        let meta = await PageMetadata.fetch(url: "https://cs128.org/missing", transport: transport)
        XCTAssertNil(meta.title)
        XCTAssertNil(meta.description)
        XCTAssertNil(meta.siteName)
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testFetchTransportErrorGivesNils() async {
        let meta = await PageMetadata.fetch(url: "https://cs128.org", transport: FailingTransport())
        XCTAssertNil(meta.title)
        XCTAssertNil(meta.description)
        XCTAssertNil(meta.siteName)
    }

    func testFetchNonHTTPURLsMakeNoRequest() async {
        let transport = MockTransport { _ in (200, self.pageHTML) }
        for url in ["chrome://settings", "ftp://example.com/a", "file:///etc/hosts", "about:blank", "not a url", ""] {
            let meta = await PageMetadata.fetch(url: url, transport: transport)
            XCTAssertNil(meta.title, url)
            XCTAssertNil(meta.description, url)
            XCTAssertNil(meta.siteName, url)
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testFetchFallsBackToLatin1WhenNotUTF8() async {
        var bytes = Data("<title>Caf".utf8)
        bytes.append(0xE9)   // "é" in ISO-8859-1, invalid as UTF-8
        bytes.append(Data("</title>".utf8))
        let transport = MockTransport { _ in (200, bytes) }
        let meta = await PageMetadata.fetch(url: "https://example.fr", transport: transport)
        XCTAssertEqual(meta.title, "Caf\u{E9}")
    }
}
