import Testing
import Foundation
@testable import tmrc

struct AskTests {

    @Test("Ask with empty index")
    func askEmptyIndex() throws {
        let tmp = FileManager.default.temporaryDirectory.path + "/tmrc-ask-\(UUID().uuidString)"
        let dbPath = (tmp as NSString).appendingPathComponent("default.sqlite")
        try FileManager.default.createDirectory(atPath: (dbPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tmp) }

        let indexManager = IndexManager(dbPath: dbPath)
        let engine = AskEngine(indexManager: indexManager, session: "default", defaultRange: "24h")
        let (answer, segments) = try engine.ask(query: "anything", since: nil, until: nil)
        #expect(segments.isEmpty)
        #expect(answer.contains("No segments") || answer.contains("no segments"))
    }
}
