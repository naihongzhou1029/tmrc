import Foundation

/// Parse relative ("1h ago", "yesterday") and absolute ("2025-02-15 14:32:00") time ranges. Uses local timezone.
public struct TimeRangeParser {
    private let calendar = Calendar.current
    private let now: Date

    public init(now: Date = Date()) {
        self.now = now
    }

    /// Parse a single time expression to a Date. Relative: "now", "1h ago", "2h ago", "yesterday". Absolute: "YYYY-MM-DD HH:MM:SS" (24h).
    public func parse(_ expr: String) -> Date? {
        let s = expr.trimmingCharacters(in: .whitespaces).lowercased()
        if s == "now" || s.isEmpty {
            return now
        }
        if let date = parseRelative(s) {
            return date
        }
        if let date = parseAbsolute(expr.trimmingCharacters(in: .whitespaces)) {
            return date
        }
        return nil
    }

    /// Parse default range string (e.g. "24h") to (start, end). "24h" = last 24 hours ending now.
    public func parseDefaultRange(_ range: String) -> (Date, Date) {
        let end = now
        let start: Date
        if range.hasSuffix("h"), let h = Int(range.dropLast()) {
            start = calendar.date(byAdding: .hour, value: -h, to: end) ?? end
        } else if range.hasSuffix("d"), let d = Int(range.dropLast()) {
            start = calendar.date(byAdding: .day, value: -d, to: end) ?? end
        } else {
            start = calendar.date(byAdding: .hour, value: -24, to: end) ?? end
        }
        return (start, end)
    }

    private func parseRelative(_ s: String) -> Date? {
        if s == "yesterday" {
            return calendar.date(byAdding: .day, value: -1, to: now)
        }
        let pattern = #"(\d+)\s*(h|m|min|d)\s*ago"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              match.numberOfRanges >= 3,
              let numRange = Range(match.range(at: 1), in: s),
              let unitRange = Range(match.range(at: 2), in: s),
              let num = Int(s[numRange]) else {
            return nil
        }
        let unit = String(s[unitRange])
        let value: Int
        if unit == "h" { value = -num }
        else if unit == "m" || unit == "min" { value = -num }
        else if unit == "d" { value = -num }
        else { return nil }
        if unit == "h" {
            return calendar.date(byAdding: .hour, value: value, to: now)
        }
        if unit == "d" {
            return calendar.date(byAdding: .day, value: value, to: now)
        }
        return calendar.date(byAdding: .minute, value: value, to: now)
    }

    private func parseAbsolute(_ s: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: s)
    }
}
