import Testing
import Foundation
@testable import tmrc

struct SearchTests {

    @Test("Search with empty index")
    func searchEmptyIndex() throws {
        let tmp = FileManager.default.temporaryDirectory.path + "/tmrc-search-\(UUID().uuidString)"
        let dbPath = (tmp as NSString).appendingPathComponent("default.sqlite")
        try FileManager.default.createDirectory(atPath: (dbPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tmp) }

        let indexManager = IndexManager(dbPath: dbPath)
        let engine = SearchEngine(indexManager: indexManager, session: "default", defaultRange: "24h")
        let (answer, segments) = try engine.search(query: "anything", since: nil, until: nil)
        #expect(segments.isEmpty)
        #expect(answer.contains("No segments") || answer.contains("no segments"))
    }

    @Test("Search with no matches returns clear message")
    func searchNoMatches() throws {
        let tmp = FileManager.default.temporaryDirectory.path + "/tmrc-search-\(UUID().uuidString)"
        let dbPath = (tmp as NSString).appendingPathComponent("default.sqlite")
        try FileManager.default.createDirectory(atPath: (dbPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tmp) }

        var indexManager = IndexManager(dbPath: dbPath)
        let seg = IndexSegment(
            id: "s1",
            session: "default",
            startTime: Date(),
            endTime: Date().addingTimeInterval(10),
            monotonicStart: 0,
            monotonicEnd: 1,
            ocrText: "hello world",
            sttText: nil,
            filePath: "/tmp/s1.mp4",
            status: "indexed"
        )
        try indexManager.upsert(seg)
        let engine = SearchEngine(indexManager: indexManager, session: "default", defaultRange: "24h")
        let (answer, segments) = try engine.search(query: "nonexistentkeyword", since: nil, until: nil)
        #expect(segments.isEmpty)
        #expect(answer.contains("No matches") || answer.contains("no matches"))
        #expect(answer.contains("Total recorded span"))
    }

    @Test("Search with matches includes citation format YYYY-MM-DD HH:MM:SS")
    func searchCitationFormat() throws {
        let tmp = FileManager.default.temporaryDirectory.path + "/tmrc-search-\(UUID().uuidString)"
        let dbPath = (tmp as NSString).appendingPathComponent("default.sqlite")
        try FileManager.default.createDirectory(atPath: (dbPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tmp) }

        var indexManager = IndexManager(dbPath: dbPath)
        let seg = IndexSegment(
            id: "seg1",
            session: "default",
            startTime: Date(),
            endTime: Date().addingTimeInterval(10),
            monotonicStart: 0,
            monotonicEnd: 1,
            ocrText: "foo bar",
            sttText: nil,
            filePath: "/tmp/s1.mp4",
            status: "indexed"
        )
        try indexManager.upsert(seg)
        let engine = SearchEngine(indexManager: indexManager, session: "default", defaultRange: "24h")
        let (answer, segments) = try engine.search(query: "foo", since: nil, until: nil)
        #expect(!segments.isEmpty)
        let citationPattern = #"\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}"#
        #expect(answer.range(of: citationPattern, options: .regularExpression) != nil)
        #expect(answer.contains("segment seg1") || answer.contains("seg1"))
    }
}
