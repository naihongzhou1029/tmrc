import Foundation
import GRDB

/// Schema version for migrations.
public let indexSchemaVersion: Int = 1

/// Segment row for search and export.
public struct IndexSegment: Codable, FetchableRecord, PersistableRecord {
    public var id: String
    public var session: String
    public var startTime: Date
    public var endTime: Date
    public var monotonicStart: Int64
    public var monotonicEnd: Int64
    public var ocrText: String?
    public var sttText: String?
    public var filePath: String
    public var status: String

    public static let databaseTableName = "segments"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let session = Column(CodingKeys.session)
        static let startTime = Column(CodingKeys.startTime)
        static let endTime = Column(CodingKeys.endTime)
        static let monotonicStart = Column(CodingKeys.monotonicStart)
        static let monotonicEnd = Column(CodingKeys.monotonicEnd)
        static let ocrText = Column(CodingKeys.ocrText)
        static let sttText = Column(CodingKeys.sttText)
        static let filePath = Column(CodingKeys.filePath)
        static let status = Column(CodingKeys.status)
    }
}

/// Create schema and run migrations.
public func createIndexSchema(_ db: Database) throws {
    try db.create(table: IndexSegment.databaseTableName, ifNotExists: true) { t in
        t.primaryKey(["id"])
        t.column("id", .text).notNull()
        t.column("session", .text).notNull()
        t.column("startTime", .datetime).notNull()
        t.column("endTime", .datetime).notNull()
        t.column("monotonicStart", .integer).notNull()
        t.column("monotonicEnd", .integer).notNull()
        t.column("ocrText", .text)
        t.column("sttText", .text)
        t.column("filePath", .text).notNull()
        t.column("status", .text).notNull()
    }
    try db.execute(sql: "CREATE TABLE IF NOT EXISTS schema_version (version INTEGER NOT NULL)")
    try db.execute(sql: "INSERT OR REPLACE INTO schema_version (version) VALUES (?)", arguments: [indexSchemaVersion])
}
