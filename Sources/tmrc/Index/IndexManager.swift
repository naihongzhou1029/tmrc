import Foundation
import GRDB

/// CRUD and query for segment index (keyword search, time range).
public struct IndexManager {
    public let dbPath: String
    private var dbQueue: DatabaseQueue?

    public init(dbPath: String) {
        self.dbPath = dbPath
    }

    mutating func connect() throws {
        if dbQueue == nil {
            try FileManager.default.createDirectory(atPath: (dbPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            dbQueue = try DatabaseQueue(path: dbPath)
            try dbQueue?.write { try createIndexSchema($0) }
        }
    }

    /// Insert or replace a segment.
    public mutating func upsert(_ segment: IndexSegment) throws {
        try connect()
        try dbQueue?.write { db in
            try segment.save(db)
        }
    }

    /// Query by time range (wall-clock). Returns segments overlapping [from, to].
    public mutating func segments(from: Date, to: Date, session: String) throws -> [IndexSegment] {
        try connect()
        return try dbQueue?.read { db in
            try IndexSegment
                .filter(IndexSegment.Columns.session == session)
                .filter(IndexSegment.Columns.startTime <= to)
                .filter(IndexSegment.Columns.endTime >= from)
                .order(IndexSegment.Columns.startTime)
                .fetchAll(db)
        } ?? []
    }

    /// Keyword search in OCR/STT text (simple contains). Normal mode retrieval.
    public mutating func search(keyword: String, from: Date, to: Date, session: String, limit: Int = 50) throws -> [IndexSegment] {
        try connect()
        let pattern = "%\(keyword)%"
        return try dbQueue?.read { db in
            try IndexSegment
                .filter(IndexSegment.Columns.session == session)
                .filter(IndexSegment.Columns.startTime <= to)
                .filter(IndexSegment.Columns.endTime >= from)
                .filter(
                    IndexSegment.Columns.ocrText.like(pattern) ||
                    IndexSegment.Columns.sttText.like(pattern)
                )
                .order(IndexSegment.Columns.startTime)
                .limit(limit)
                .fetchAll(db)
        } ?? []
    }

    /// Check if index has any segments (for empty-index messaging).
    public mutating func isEmpty(session: String) throws -> Bool {
        try countSegments(session: session) == 0
    }

    /// Count all segments in the session.
    public mutating func countSegments(session: String) throws -> Int {
        try connect()
        return try dbQueue?.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM segments WHERE session = ?", arguments: [session]) ?? 0
        } ?? 0
    }

    /// Fetch a single segment by id and session (for rebuild-index).
    public mutating func segment(id: String, session: String) throws -> IndexSegment? {
        try connect()
        return try dbQueue?.read { db in
            try IndexSegment
                .filter(IndexSegment.Columns.id == id)
                .filter(IndexSegment.Columns.session == session)
                .fetchOne(db)
        }
    }

    /// Latest segment by end time (for export/query).
    public mutating func lastSegment(session: String) throws -> IndexSegment? {
        try connect()
        return try dbQueue?.read { db in
            try IndexSegment
                .filter(IndexSegment.Columns.session == session)
                .order(IndexSegment.Columns.endTime.desc)
                .fetchOne(db)
        }
    }

    /// Total recorded duration in seconds (sum of segment durations) for status.
    public mutating func totalRecordedDuration(session: String) throws -> TimeInterval? {
        try connect()
        return try dbQueue?.read { db in
            // SQLite's julianday() returns days as fractional numbers. Subtract and multiply by seconds/day (86400).
            let sql = "SELECT SUM(julianday(endTime) - julianday(startTime)) * 86400 FROM segments WHERE session = ?"
            let result = try Double.fetchOne(db, sql: sql, arguments: [session])
            guard let val = result, val > 0 else { return nil }
            return val
        }
    }

    /// Overall time range of all recorded segments in the session.
    public mutating func overallTimeRange(session: String) throws -> (start: Date, end: Date)? {
        try connect()
        return try dbQueue?.read { db in
            let row = try Row.fetchOne(db, sql: "SELECT MIN(startTime), MAX(endTime) FROM segments WHERE session = ?", arguments: [session])
            guard let row = row, let start: Date = row[0], let end: Date = row[1] else { return nil }
            return (start, end)
        }
    }

    /// Remove all segment rows (for wipe). Daemon can keep running; new segments will repopulate.
    public mutating func deleteAllSegments() throws {
        try connect()
        try dbQueue?.write { db in
            try db.execute(sql: "DELETE FROM segments")
        }
    }
}
