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

    [Fact(DisplayName = "DeleteByPaths removes rows for given paths only")]
    public void DeleteByPathsRemovesMatchingRows()
    {
        var path = Path.Combine(Path.GetTempPath(), "tmrc-index-" + Guid.NewGuid() + ".sqlite");
        var store = new IndexStore(path);

        var t = new DateTimeOffset(2025, 2, 15, 14, 0, 0, TimeSpan.Zero);
        store.UpsertSegment("id-a", t, t.AddMinutes(1), "C:/segments/a.mp4", null, null);
        store.UpsertSegment("id-b", t.AddMinutes(1), t.AddMinutes(2), "C:/segments/b.mp4", null, null);
        store.UpsertSegment("id-c", t.AddMinutes(2), t.AddMinutes(3), "C:/segments/c.mp4", null, null);

        store.DeleteByPaths(new[] { "C:/segments/b.mp4" });

        var list = store.ListAllSegments();
        Assert.Equal(2, list.Count);
        Assert.Equal("id-a", list[0].Id);
        Assert.Equal("id-c", list[1].Id);
    }

    [Fact(DisplayName = "GetMaxWriteOrder returns 0 for empty DB and max after inserts")]
    public void GetMaxWriteOrder_ReturnsMax()
    {
        var path = Path.Combine(Path.GetTempPath(), "tmrc-index-" + Guid.NewGuid() + ".sqlite");
        var store = new IndexStore(path);
        Assert.Equal(0L, store.GetMaxWriteOrder());

        var t = new DateTimeOffset(2025, 2, 15, 14, 0, 0, TimeSpan.Zero);
        store.UpsertSegment("a", t, t.AddMinutes(1), "/a/a.mp4", null, null, writeOrder: 10L);
        Assert.Equal(10L, store.GetMaxWriteOrder());
        store.UpsertSegment("b", t.AddMinutes(1), t.AddMinutes(2), "/a/b.mp4", null, null, writeOrder: 20L);
        Assert.Equal(20L, store.GetMaxWriteOrder());
    }

    [Fact(DisplayName = "ListAllSegments orders by write_order when present")]
    public void ListAllSegments_OrdersByWriteOrder()
    {
        var path = Path.Combine(Path.GetTempPath(), "tmrc-index-" + Guid.NewGuid() + ".sqlite");
        var store = new IndexStore(path);

        var t1 = new DateTimeOffset(2025, 2, 15, 14, 0, 0, TimeSpan.Zero);
        var t2 = t1.AddMinutes(1);
        var t3 = t1.AddMinutes(2);
        store.UpsertSegment("late", t3, t3.AddMinutes(1), "/late.mp4", null, null, writeOrder: 1L);
        store.UpsertSegment("early", t1, t1.AddMinutes(1), "/early.mp4", null, null, writeOrder: 3L);
        store.UpsertSegment("mid", t2, t2.AddMinutes(1), "/mid.mp4", null, null, writeOrder: 2L);

        var list = store.ListAllSegments();
        Assert.Equal(3, list.Count);
        Assert.Equal("late", list[0].Id);
        Assert.Equal("mid", list[1].Id);
        Assert.Equal("early", list[2].Id);
    }
}

