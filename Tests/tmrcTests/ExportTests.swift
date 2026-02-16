import Testing
import Foundation
@testable import tmrc

struct ExportTests {

    @Test("Export with empty index throws noSegments")
    func exportEmptyIndex() throws {
        let tmp = FileManager.default.temporaryDirectory.path + "/tmrc-export-\(UUID().uuidString)"
        let dbPath = (tmp as NSString).appendingPathComponent("index/default.sqlite")
        let segDir = (tmp as NSString).appendingPathComponent("segments")
        try FileManager.default.createDirectory(atPath: (dbPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: segDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tmp) }

        let storage = StorageManager(storageRoot: tmp)
        var indexManager = IndexManager(dbPath: storage.indexPath(session: "default"))
        let engine = ExportEngine(storage: storage, indexManager: indexManager, session: "default")
        #expect(throws: ExportError.self) {
            try engine.export(from: Date(), to: Date().addingTimeInterval(60), query: nil, outputPath: "/tmp/out.mp4", format: "mp4")
        }
    }

    @Test("Export with missing segment file throws missingSegment")
    func exportMissingSegment() throws {
        let tmp = FileManager.default.temporaryDirectory.path + "/tmrc-export-\(UUID().uuidString)"
        let dbPath = (tmp as NSString).appendingPathComponent("index/default.sqlite")
        let segDir = (tmp as NSString).appendingPathComponent("segments")
        try FileManager.default.createDirectory(atPath: (dbPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: segDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tmp) }

        var indexManager = IndexManager(dbPath: dbPath)
        let segment = IndexSegment(
            id: "missing-seg",
            session: "default",
            startTime: Date(),
            endTime: Date().addingTimeInterval(10),
            monotonicStart: 0,
            monotonicEnd: 1,
            ocrText: nil,
            sttText: nil,
            filePath: (segDir as NSString).appendingPathComponent("missing-seg.mp4"),
            status: "pending"
        )
        try indexManager.upsert(segment)

        let storage = StorageManager(storageRoot: tmp)
        let engine = ExportEngine(storage: storage, indexManager: indexManager, session: "default")
        do {
            try engine.export(from: Date().addingTimeInterval(-1), to: Date().addingTimeInterval(20), query: nil, outputPath: "/tmp/out.mp4", format: "mp4")
            #expect(Bool(false), "Expected ExportError.missingSegment")
        } catch ExportError.missingSegment(let id, _) {
            #expect(id == "missing-seg")
        } catch {
            throw error
        }
    }

    @Test("Export requires from/to or query")
    func exportRequiresRangeOrQuery() throws {
        let tmp = FileManager.default.temporaryDirectory.path + "/tmrc-export-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tmp) }
        let storage = StorageManager(storageRoot: tmp)
        var indexManager = IndexManager(dbPath: storage.indexPath(session: "default"))
        let seg = IndexSegment(
            id: "s1",
            session: "default",
            startTime: Date(),
            endTime: Date().addingTimeInterval(5),
            monotonicStart: 0,
            monotonicEnd: 1,
            ocrText: "x",
            sttText: nil,
            filePath: (tmp as NSString).appendingPathComponent("segments/s1.mp4"),
            status: "indexed"
        )
        try indexManager.upsert(seg)
        FileManager.default.createFile(atPath: seg.filePath, contents: Data())
        let engine = ExportEngine(storage: storage, indexManager: indexManager, session: "default")
        #expect(throws: ExportError.self) {
            try engine.export(from: nil, to: nil, query: nil, outputPath: "/tmp/out.mp4", format: "mp4")
        }
    }
}
