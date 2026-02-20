using System;
using System.Globalization;

namespace Tmrc.Core.Recall;

public readonly record struct TimeRange(DateTimeOffset From, DateTimeOffset To);

public static class TimeRangeParser
{
    public static TimeRange ParseRelative(string from, string to, DateTimeOffset now)
    {
        var start = ParsePoint(from, now, isStart: true);
        var end = ParsePoint(to, now, isStart: false);
        return new TimeRange(start, end);
    }

    public static DateTimeOffset ParseAbsolute(string input, DateTimeOffset? now = null)
    {
        now ??= DateTimeOffset.Now;
        if (string.Equals(input, "now", StringComparison.OrdinalIgnoreCase))
        {
            return now.Value;
        }

        if (DateTimeOffset.TryParseExact(
                input,
                "yyyy-MM-dd HH:mm:ss",
                CultureInfo.InvariantCulture,
                DateTimeStyles.AssumeLocal,
                out var dt))
        {
            return dt;
        }

        if (DateTimeOffset.TryParse(input, CultureInfo.CurrentCulture,
                DateTimeStyles.AssumeLocal, out dt))
        {
            return dt;
        }

        throw new FormatException($"Unrecognized time format: {input}");
    }

    private static DateTimeOffset ParsePoint(string expr, DateTimeOffset now, bool isStart)
    {
        if (string.IsNullOrWhiteSpace(expr) || string.Equals(expr, "now", StringComparison.OrdinalIgnoreCase))
        {
            return now;
        }

        expr = expr.Trim();

        if (expr.EndsWith("ago", StringComparison.OrdinalIgnoreCase))
        {
            var core = expr[..^3].Trim();
            // Support "1h ago" and "1 h ago"
            var parts = core.Split(' ', StringSplitOptions.RemoveEmptyEntries);
            if (parts.Length == 1)
            {
                // Assume hours if unit omitted, e.g. "1h"
                parts = new[] { core[..^1], core[^1..] };
            }

            if (parts.Length == 2 &&
                double.TryParse(parts[0], NumberStyles.Float, CultureInfo.InvariantCulture, out var amount))
            {
                var unit = parts[1].ToLowerInvariant();
                return unit switch
                {
                    "s" or "sec" or "secs" or "second" or "seconds" => now - TimeSpan.FromSeconds(amount),
                    "m" or "min" or "mins" or "minute" or "minutes" => now - TimeSpan.FromMinutes(amount),
                    "h" or "hr" or "hrs" or "hour" or "hours" => now - TimeSpan.FromHours(amount),
                    "d" or "day" or "days" => now - TimeSpan.FromDays(amount),
                    _ => throw new FormatException($"Unsupported relative unit: {unit}")
                };
            }
        }

        if (string.Equals(expr, "yesterday", StringComparison.OrdinalIgnoreCase))
        {
            var local = now.ToLocalTime();
            var date = local.Date.AddDays(-1);
            var start = new DateTimeOffset(date, local.Offset);
            var end = new DateTimeOffset(date.AddDays(1).AddTicks(-1), local.Offset);
            return isStart ? start : end;
        }

        return ParseAbsolute(expr, now);
    }
}

