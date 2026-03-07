import Foundation

/// Ask: keyword search in index, template answer with citations (timestamp + segment ref).
public struct AskEngine {
    public let indexManager: IndexManager
    public let session: String
    public let defaultRange: String
    private let timeParser = TimeRangeParser()

    public init(indexManager: IndexManager, session: String, defaultRange: String = "24h") {
        self.indexManager = indexManager
        self.session = session
        self.defaultRange = defaultRange
    }

    /// Run query; returns answer text and segment refs. Empty index or no matches return a clear message.
    public func ask(query: String, since: String?, until: String?) throws -> (answer: String, segments: [IndexSegment]) {
        var index = indexManager
        if try index.isEmpty(session: session) {
            return ("No segments indexed yet. Try recording first, or check tmrc status.", [])
        }
        let (from, to) = resolveRange(since: since, until: until)
        let segments = try index.search(keyword: query, from: from, to: to, session: session)
        if segments.isEmpty {
            var msg = "No matches for \"\(query)\" in the given time range."
            if let range = try index.overallTimeRange(session: session) {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                msg += " (Total recorded span: \(formatter.string(from: range.start)) to \(formatter.string(from: range.end)))"
            }
            return (msg, [])
        }
        let citations = segments.map { seg in
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            formatter.timeZone = TimeZone.current
            return "\(formatter.string(from: seg.startTime)) (segment \(seg.id))"
        }
        let answer = "Found \(segments.count) segment(s):\n" + citations.joined(separator: "\n")
        return (answer, segments)
    }

    private func resolveRange(since: String?, until: String?) -> (Date, Date) {
        if let since = since, let until = until,
           let from = timeParser.parse(since),
           let to = timeParser.parse(until) {
            return (from, to)
        }
        return timeParser.parseDefaultRange(defaultRange)
    }
}
