import Testing
import Foundation
@testable import tmrc

struct IndexTests {

    @Test("Index create and read")
    func indexCreateAndRead() throws {
        let tmp = FileManager.default.temporaryDirectory.path + "/tmrc-index-\(UUID().uuidString)"
        let dbPath = (tmp as NSString).appendingPathComponent("test.sqlite")
        try FileManager.default.createDirectory(atPath: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tmp) }

        var index = IndexManager(dbPath: dbPath)
        let segment = IndexSegment(
            id: "seg1",
            session: "default",
            startTime: Date(),
            endTime: Date().addingTimeInterval(10),
            monotonicStart: 0,
            monotonicEnd: 1,
            ocrText: "hello world",
            sttText: nil,
            filePath: "/tmp/seg1.mp4",
            status: "ok"
        )
        try index.upsert(segment)
        let results = try index.segments(from: Date().addingTimeInterval(-1), to: Date().addingTimeInterval(20), session: "default")
        #expect(results.count == 1)
        #expect(results[0].id == "seg1")
        #expect(results[0].ocrText == "hello world")
    }

    @Test("Index schema - tables exist")
    func indexSchema() throws {
        let tmp = FileManager.default.temporaryDirectory.path + "/tmrc-schema-\(UUID().uuidString)"
        let dbPath = (tmp as NSString).appendingPathComponent("test.sqlite")
        try FileManager.default.createDirectory(atPath: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tmp) }
        var index = IndexManager(dbPath: dbPath)
        _ = try index.isEmpty(session: "default")
        #expect(FileManager.default.fileExists(atPath: dbPath))
    }
}
