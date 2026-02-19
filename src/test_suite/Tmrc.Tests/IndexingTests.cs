using System;
using System.IO;
using Tmrc.Core.Indexing;
using Xunit;

namespace Tmrc.Tests;

public class IndexingTests
{
    [Fact(DisplayName = "Index schema create and read")]
    public void IndexSchemaCreateAndRead()
    {
        var path = Path.Combine(Path.GetTempPath(), "tmrc-index-" + Guid.NewGuid() + ".sqlite");
        var store = new IndexStore(path);

        var start = new DateTimeOffset(2025, 2, 15, 14, 0, 0, TimeSpan.Zero);
        var end = start.AddMinutes(5);

        store.UpsertSegment(
            id: "seg-1",
            start: start,
            end: end,
            path: "C:/segments/seg-1.mp4",
            ocrText: "hello world",
            sttText: "speech text");

        var rows = store.QueryByTimeRange(
            from: start.AddMinutes(-1),
            to: end.AddMinutes(1));

        Assert.Single(rows);
        var row = rows[0];
        Assert.Equal("seg-1", row.Id);
        Assert.Equal(start, row.Start);
        Assert.Equal(end, row.End);
        Assert.Equal("C:/segments/seg-1.mp4", row.Path);
        Assert.Equal("hello world", row.OcrText);
        Assert.Equal("speech text", row.SttText);
    }
}

