import XCTest
@testable import Tofu

@MainActor final class ScreenMemoryTests: XCTestCase {
    private let subject = Subject(name: "CS128", details: "Intro CS in C++", preset: .full,
                                  sites: ["https://cs128.org"])
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func note(_ minutes: Double, onTask: Bool = true, subjectID: UUID? = nil) -> MemoryNote {
        MemoryNote(subjectID: subjectID ?? subject.id, subjectName: subject.name,
                   date: start.addingTimeInterval(minutes * 60), summary: "note \(Int(minutes))",
                   topics: ["lists"], sites: ["cs128.org"], onTask: onTask)
    }

    // MARK: Store

    func testStoreKeepsNewestFirstAndCapsPerSubject() {
        let store = MemoryStore(fileURL: nil)
        for minute in 0..<(MemoryStore.maxNotesPerSubject + 5) { store.add(note(Double(minute))) }
        let notes = store.notes(for: subject.id)
        XCTAssertEqual(notes.count, MemoryStore.maxNotesPerSubject)
        XCTAssertEqual(notes.first?.summary, "note \(MemoryStore.maxNotesPerSubject + 4)")
        XCTAssertEqual(notes.last?.summary, "note 5")
    }

    func testLatestSkipsOffTaskNotes() {
        let store = MemoryStore(fileURL: nil)
        store.add(note(1))
        store.add(note(2, onTask: false))
        XCTAssertEqual(store.latest(forSubjectNamed: "CS128")?.summary, "note 1")
        XCTAssertNil(store.latest(forSubjectNamed: "Math"))
    }

    func testDeleteAndForget() {
        let store = MemoryStore(fileURL: nil)
        let other = UUID()
        store.add(note(1))
        store.add(note(2, subjectID: other))
        store.delete(store.notes(for: subject.id)[0].id)
        XCTAssertTrue(store.notes(for: subject.id).isEmpty)
        store.forget(subjectID: other)
        XCTAssertTrue(store.notes.isEmpty)
    }

    func testStorePersistsToDisk() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("memory-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        MemoryStore(fileURL: url).add(note(3))
        XCTAssertEqual(MemoryStore(fileURL: url).notes.map(\.summary), ["note 3"])
    }

    // MARK: Digest

    func testPromptBlockListsNotesWithExtras() {
        XCTAssertEqual(MemoryDigest.promptBlock([]), "")
        let block = MemoryDigest.promptBlock([note(1), note(2, onTask: false)])
        XCTAssertTrue(block.contains("note 1"))
        XCTAssertTrue(block.contains("topics: lists"))
        XCTAssertTrue(block.contains("sites: cs128.org"))
        XCTAssertTrue(block.contains("off task"))
    }

    // MARK: Extractor

    func testParseCleansTheModelsJSON() {
        let reply = #"Here: {"summary":"  Debugging MP3 linked list tests in VS Code. ","topics":["linked lists",""],"sites":["https://cs128.org/mp3"],"apps":["Visual Studio Code"],"on_task":true}"#
        let parsed = ScreenMemoryExtractor.parse(reply, subject: subject, date: start)
        XCTAssertEqual(parsed?.summary, "Debugging MP3 linked list tests in VS Code.")
        XCTAssertEqual(parsed?.topics, ["linked lists"])
        XCTAssertEqual(parsed?.sites, ["cs128.org"])
        XCTAssertEqual(parsed?.apps, ["Visual Studio Code"])
        XCTAssertEqual(parsed?.onTask, true)
        XCTAssertEqual(parsed?.subjectID, subject.id)
        XCTAssertNil(ScreenMemoryExtractor.parse(#"{"summary":""}"#, subject: subject, date: start))
        XCTAssertNil(ScreenMemoryExtractor.parse("nope", subject: subject, date: start))
    }

    func testSystemPromptNamesTheSubjectAndAsksForPrivacy() {
        let prompt = ScreenMemoryExtractor.systemPrompt(subject: subject, recent: [note(1)])
        XCTAssertTrue(prompt.contains("CS128"))
        XCTAssertTrue(prompt.contains("Intro CS in C++"))
        XCTAssertTrue(prompt.contains("never copy personal data"))
        XCTAssertTrue(prompt.contains("note 1"))
    }

    func testVisionMessageEncodesImageParts() throws {
        let message = ChatWireMessage.user("Describe", jpegs: [Data([1, 2, 3])])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(message)) as? [String: Any])
        let parts = try XCTUnwrap(json["content"] as? [[String: Any]])
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts[0]["type"] as? String, "text")
        XCTAssertEqual(parts[1]["type"] as? String, "image_url")
        let image = try XCTUnwrap(parts[1]["image_url"] as? [String: String])
        XCTAssertEqual(image["url"], "data:image/jpeg;base64,AQID")
        XCTAssertEqual(image["detail"], "low")
        // Plain messages keep a string content.
        let plain = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(ChatWireMessage.user("hi"))) as? [String: Any])
        XCTAssertEqual(plain["content"] as? String, "hi")
    }

    func testScaledSizeKeepsAspectRatio() {
        XCTAssertEqual(ScreenCapturer.scaledSize(width: 3024, height: 1964, maxPixels: 1600).width, 1600)
        XCTAssertEqual(ScreenCapturer.scaledSize(width: 3024, height: 1964, maxPixels: 1600).height, 1039)
        XCTAssertEqual(ScreenCapturer.scaledSize(width: 1200, height: 800, maxPixels: 1600).width, 1200)
    }

    // MARK: Recorder

    private final class FakeCapturer: ScreenCapturing {
        var hasPermission = true
        var captures = 0
        func capture() async throws -> Data {
            captures += 1
            return Data([0xFF, 0xD8])
        }
    }

    private func recorder(store: MemoryStore, capturer: FakeCapturer, enabled: Bool = true, paused: Bool = false,
                          transport: MockTransport) -> ScreenMemoryRecorder {
        ScreenMemoryRecorder(capturer: capturer,
                             extractor: ScreenMemoryExtractor(apiKey: { "sk" }, transport: transport),
                             store: store, isEnabled: { enabled }, isPaused: { paused },
                             clock: { self.start }, interval: 3600)
    }

    private let modelReply = MockTransport.json(
        #"{"choices":[{"message":{"content":"{\"summary\":\"Reading the MP3 spec.\",\"topics\":[\"MP3\"],\"sites\":[\"cs128.org\"],\"apps\":[],\"on_task\":true}"}}]}"#)

    func testRecordNowCapturesDescribesAndStores() async {
        let store = MemoryStore(fileURL: nil)
        let capturer = FakeCapturer()
        let transport = MockTransport { _ in (200, self.modelReply) }
        let rec = recorder(store: store, capturer: capturer, transport: transport)
        rec.start(subject: subject)
        let note = await rec.recordNow()
        rec.stop()
        XCTAssertEqual(note?.summary, "Reading the MP3 spec.")
        XCTAssertEqual(store.notes(for: subject.id).count, 1)
        XCTAssertEqual(capturer.captures, 1)
        let body = String(data: transport.requests[0].httpBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("image_url"))
    }

    func testRecordNowSkipsWhenOffPausedUnpermittedOrIdle() async {
        let transport = MockTransport { _ in (200, self.modelReply) }
        let store = MemoryStore(fileURL: nil)

        let idle = recorder(store: store, capturer: FakeCapturer(), transport: transport)
        let idleNote = await idle.recordNow()
        XCTAssertNil(idleNote)   // never started

        let off = recorder(store: store, capturer: FakeCapturer(), enabled: false, transport: transport)
        off.start(subject: subject)
        let offNote = await off.recordNow()
        XCTAssertNil(offNote)

        let paused = recorder(store: store, capturer: FakeCapturer(), paused: true, transport: transport)
        paused.start(subject: subject)
        let pausedNote = await paused.recordNow()
        XCTAssertNil(pausedNote)

        let noPermission = FakeCapturer()
        noPermission.hasPermission = false
        let blocked = recorder(store: store, capturer: noPermission, transport: transport)
        blocked.start(subject: subject)
        let blockedNote = await blocked.recordNow()
        XCTAssertNil(blockedNote)
        XCTAssertEqual(noPermission.captures, 0)

        XCTAssertTrue(store.notes.isEmpty)
        XCTAssertTrue(transport.requests.isEmpty)
        [off, paused, blocked].forEach { $0.stop() }
    }

    func testScreenMemorySettingDefaultsOnAndLoadsFromOldFiles() throws {
        XCTAssertTrue(AppSettings().screenMemoryEnabled)
        let json = #"{"displayName":"A","discordEnabled":false,"giveUpTemplate":"x","channelCache":{}}"#
        XCTAssertTrue(try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8)).screenMemoryEnabled)
    }
}
