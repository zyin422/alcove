import Foundation
import Observation
import os

/// One thing remembered from a screenshot taken during a lock-in. Only this text is kept: the screenshot itself is
/// sent to OpenAI to be described and then dropped, never written to disk.
struct MemoryNote: Codable, Identifiable, Hashable {
    var id: UUID
    var subjectID: UUID
    var subjectName: String
    var date: Date
    /// One or two sentences: what was on screen and where the work stood.
    var summary: String
    /// Concepts, chapters or tasks seen, e.g. "linked lists", "MP3".
    var topics: [String]
    /// Websites seen in use (hosts).
    var sites: [String]
    /// Apps seen in use.
    var apps: [String]
    /// False when the screen showed something unrelated to the subject.
    var onTask: Bool

    init(id: UUID = UUID(), subjectID: UUID, subjectName: String, date: Date, summary: String,
         topics: [String] = [], sites: [String] = [], apps: [String] = [], onTask: Bool = true) {
        self.id = id
        self.subjectID = subjectID
        self.subjectName = subjectName
        self.date = date
        self.summary = summary
        self.topics = topics
        self.sites = sites
        self.apps = apps
        self.onTask = onTask
    }
}

/// All memory notes, persisted as `memory.json` next to `store.json`. Observable so the subject page updates live.
@Observable @MainActor final class MemoryStore {
    /// Oldest notes beyond this many per subject are dropped.
    static let maxNotesPerSubject = 120

    private(set) var notes: [MemoryNote] = []
    @ObservationIgnored private let fileURL: URL?

    /// nil keeps everything in memory (tests).
    init(fileURL: URL?) {
        self.fileURL = fileURL
        notes = Self.load(from: fileURL)
    }

    static func defaultURL() -> URL {
        Store.defaultURL().deletingLastPathComponent().appendingPathComponent("memory.json", isDirectory: false)
    }

    /// Newest first.
    func notes(for subjectID: UUID) -> [MemoryNote] {
        notes.filter { $0.subjectID == subjectID }.sorted { $0.date > $1.date }
    }

    func latest(forSubjectNamed name: String) -> MemoryNote? {
        notes.filter { $0.subjectName == name && $0.onTask }.max { $0.date < $1.date }
    }

    func add(_ note: MemoryNote) {
        notes.append(note)
        let mine = notes(for: note.subjectID)
        if mine.count > Self.maxNotesPerSubject {
            let drop = Set(mine.dropFirst(Self.maxNotesPerSubject).map(\.id))
            notes.removeAll { drop.contains($0.id) }
        }
        save()
    }

    func delete(_ id: UUID) {
        notes.removeAll { $0.id == id }
        save()
    }

    func forget(subjectID: UUID) {
        notes.removeAll { $0.subjectID == subjectID }
        save()
    }

    func forgetAll() {
        notes = []
        save()
    }

    private func save() {
        guard let fileURL else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try Store.makeEncoder().encode(notes).write(to: fileURL, options: .atomic)
        } catch {
            Log.storage.error("Saving memory.json failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func load(from url: URL?) -> [MemoryNote] {
        guard let url, let data = try? Data(contentsOf: url) else { return [] }
        do {
            return try Store.makeDecoder().decode([MemoryNote].self, from: data)
        } catch {
            Log.storage.error("memory.json unreadable: \(String(describing: error), privacy: .public)")
            return []
        }
    }
}

/// Turns notes into text for prompts (chat assistant, setup agent) and the companion. Pure.
enum MemoryDigest {
    /// "Oct 24, 14:05 — Working through MP3 linked list tests in VS Code. (topics: linked lists; sites: cs128.org)"
    static func lines(_ notes: [MemoryNote], limit: Int = 8) -> [String] {
        notes.prefix(limit).map { note in
            var extras: [String] = []
            if !note.topics.isEmpty { extras.append("topics: " + note.topics.joined(separator: ", ")) }
            if !note.sites.isEmpty { extras.append("sites: " + note.sites.joined(separator: ", ")) }
            if !note.apps.isEmpty { extras.append("apps: " + note.apps.joined(separator: ", ")) }
            if !note.onTask { extras.append("off task") }
            let stamp = note.date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
            return "\(stamp) — \(note.summary)" + (extras.isEmpty ? "" : " (\(extras.joined(separator: "; ")))")
        }
    }

    /// A prompt block, or "" when there is nothing to remember.
    static func promptBlock(_ notes: [MemoryNote], limit: Int = 8) -> String {
        let lines = lines(notes, limit: limit)
        guard !lines.isEmpty else { return "" }
        return "What you remember from earlier screenshots of this work (newest first):\n- "
            + lines.joined(separator: "\n- ")
    }
}

/// Describes one screenshot with the vision model and returns a note. The prompt asks for JSON only.
struct ScreenMemoryExtractor {
    let apiKey: () -> String?
    var transport: HTTPTransport = URLSessionTransport()

    enum Failure: Error, Equatable {
        case noKey
        case unreadableReply
    }

    func describe(jpeg: Data, subject: Subject, recent: [MemoryNote], at date: Date) async throws -> MemoryNote {
        guard let key = apiKey()?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            throw Failure.noKey
        }
        let client = OpenAIChatClient(apiKey: key, transport: transport, timeout: 40)
        let completion = try await client.complete(
            messages: [.system(Self.systemPrompt(subject: subject, recent: recent)),
                       .user("Describe this screenshot as JSON.", jpegs: [jpeg])],
            tools: [], maxTokens: 400, json: true)
        guard let note = Self.parse(completion.content ?? "", subject: subject, date: date) else {
            throw Failure.unreadableReply
        }
        return note
    }

    static func systemPrompt(subject: Subject, recent: [MemoryNote]) -> String {
        var prompt = """
        You keep a study journal for someone locked in on "\(subject.name)".
        """
        if !subject.details.isEmpty { prompt += " They describe it as: \(subject.details)" }
        prompt += """

        You get a screenshot of their screen. Write what they are working on so that later you can remind them \
        where they left off and help set up their next session. Be concrete (chapter, problem, file, page) and \
        never copy personal data such as messages, names, emails or passwords.
        Reply with one JSON object: {"summary": one or two short sentences, "topics": [up to 5 short strings], \
        "sites": [website hosts in use, e.g. "cs128.org"], "apps": [app names in use], \
        "on_task": true if the screen relates to the subject}.
        """
        let block = MemoryDigest.promptBlock(recent, limit: 3)
        if !block.isEmpty { prompt += "\n\n" + block + "\nOnly mention what changed or is new." }
        return prompt
    }

    /// The model's JSON → a note. nil without a usable summary.
    static func parse(_ reply: String, subject: Subject, date: Date) -> MemoryNote? {
        guard let data = OpenAIChatClient.jsonObject(in: reply),
              let wire = try? JSONDecoder().decode(Wire.self, from: data) else { return nil }
        let summary = (wire.summary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty else { return nil }
        func clean(_ values: [String]?, limit: Int) -> [String] {
            Array((values ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }.prefix(limit))
        }
        return MemoryNote(subjectID: subject.id, subjectName: subject.name, date: date,
                          summary: String(summary.prefix(400)),
                          topics: clean(wire.topics, limit: 5),
                          sites: clean(wire.sites, limit: 6).map { DomainMatcher.host(of: $0) ?? $0 },
                          apps: clean(wire.apps, limit: 6),
                          onTask: wire.onTask ?? true)
    }

    private struct Wire: Decodable {
        var summary: String?
        var topics: [String]?
        var sites: [String]?
        var apps: [String]?
        var onTask: Bool?

        enum CodingKeys: String, CodingKey {
            case summary, topics, sites, apps
            case onTask = "on_task"
        }
    }
}
