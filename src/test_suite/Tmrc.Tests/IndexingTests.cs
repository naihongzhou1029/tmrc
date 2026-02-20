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

    [Fact(DisplayName = "ListAllSegments returns all rows ordered by start")]
    public void ListAllSegmentsReturnsAllOrderedByStart()
    {
        var path = Path.Combine(Path.GetTempPath(), "tmrc-index-" + Guid.NewGuid() + ".sqlite");
        var store = new IndexStore(path);

        var t1 = new DateTimeOffset(2025, 2, 15, 14, 0, 0, TimeSpan.Zero);
        var t2 = t1.AddMinutes(10);
        var t3 = t1.AddMinutes(5);

        store.UpsertSegment("seg-b", t2, t2.AddMinutes(1), "/a/b.mp4", null, null);
        store.UpsertSegment("seg-a", t1, t1.AddMinutes(1), "/a/a.mp4", null, null);
        store.UpsertSegment("seg-c", t3, t3.AddMinutes(1), "/a/c.mp4", null, null);

        var list = store.ListAllSegments();
        Assert.Equal(3, list.Count);
        Assert.Equal("seg-a", list[0].Id);
        Assert.Equal("seg-c", list[1].Id);
        Assert.Equal("seg-b", list[2].Id);
    }
}

