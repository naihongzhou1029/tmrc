using System;
using Tmrc.Core.Recall;
using Xunit;

namespace Tmrc.Tests;

public class TimeRangeParserTests
{
    [Fact(DisplayName = "Time range parsing relative")]
    public void TimeRangeRelative()
    {
        var now = new DateTimeOffset(2025, 2, 15, 15, 32, 0, TimeSpan.FromHours(8));
        var start = TimeRangeParser.ParseRelative("1h ago", "now", now).From;
        var yesterdayStart = TimeRangeParser.ParseRelative("yesterday", "now", now).From;

        Assert.Equal(now.AddHours(-1), start);
        Assert.Equal(new DateTimeOffset(2025, 2, 14, 0, 0, 0, TimeSpan.FromHours(8)), yesterdayStart);
    }

    [Fact(DisplayName = "Time range parsing absolute")]
    public void TimeRangeAbsolute()
    {
        var now = new DateTimeOffset(2025, 2, 15, 15, 32, 0, TimeSpan.FromHours(8));
        var parsed = TimeRangeParser.ParseAbsolute("2025-02-15 14:32:00", now);
        var expected = new DateTimeOffset(2025, 2, 15, 14, 32, 0, TimeSpan.FromHours(8));
        Assert.Equal(expected, parsed);
    }
}

