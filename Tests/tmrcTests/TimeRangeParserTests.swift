import Testing
import Foundation
@testable import tmrc

struct TimeRangeParserTests {

    @Test("Relative 1h ago")
    func relative1hAgo() throws {
        let now = Date()
        let parser = TimeRangeParser(now: now)
        let oneHAgo = parser.parse("1h ago")
        #expect(oneHAgo != nil)
        if let d = oneHAgo {
            let diff = now.timeIntervalSince(d)
            #expect(diff >= 3599 && diff <= 3601)
        }
    }

    @Test("Default range 24h")
    func defaultRange24h() throws {
        let now = Date()
        let parser = TimeRangeParser(now: now)
        let (start, end) = parser.parseDefaultRange("24h")
        #expect(end == now)
        #expect(start < end)
        #expect(now.timeIntervalSince(start) >= 86399 && now.timeIntervalSince(start) <= 86401)
    }

    @Test("Absolute date")
    func absoluteDate() throws {
        let parser = TimeRangeParser()
        let d = parser.parse("2025-02-15 14:32:00")
        #expect(d != nil)
    }
}
