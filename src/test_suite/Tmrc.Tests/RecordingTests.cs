using System.Collections.Generic;
using Tmrc.Core.Recording;
using Xunit;

namespace Tmrc.Tests;

public class RecordingTests
{
    [Fact(DisplayName = "Segment boundaries (event-based)")]
    public void SegmentBoundaries_EventBased()
    {
        var seg = new EventSegmenter();
        var flushed = new List<EventSegmenter.Segment>();

        // Frame 0: one event
        seg.OnFrame(frameIndex: 0, hasEvent: true, flushedSegments: flushed);
        // Frame 1: idle → should flush a segment for the prior activity
        seg.OnFrame(frameIndex: 1, hasEvent: false, flushedSegments: flushed);

        seg.FlushTail(flushed);

        Assert.Single(flushed);
        var s = flushed[0];
        Assert.True(s.StartFrame <= s.EndFrame);
    }

    [Fact(DisplayName = "Segment boundaries (burst)")]
    public void SegmentBoundaries_Burst()
    {
        var seg = new EventSegmenter();
        var flushed = new List<EventSegmenter.Segment>();

        // Simulate ~1 second of activity: 31 consecutive event frames.
        for (var i = 0; i < 31; i++)
        {
            seg.OnFrame(frameIndex: i, hasEvent: true, flushedSegments: flushed);
        }

        // Followed by one idle frame which should flush a single segment.
        seg.OnFrame(frameIndex: 31, hasEvent: false, flushedSegments: flushed);
        seg.FlushTail(flushed);

        Assert.Single(flushed);
        var s = flushed[0];
        Assert.Equal(0, s.StartFrame);
        Assert.True(s.EndFrame >= 30);
    }

    [Fact(DisplayName = "Idle frames do not create segments")]
    public void IdleFrames_DoNotCreateSegments()
    {
        var seg = new EventSegmenter();
        var flushed = new List<EventSegmenter.Segment>();

        for (var i = 0; i < 20; i++)
        {
            seg.OnFrame(frameIndex: i, hasEvent: false, flushedSegments: flushed);
        }

        seg.FlushTail(flushed);
        Assert.Empty(flushed);
    }

    [Fact(DisplayName = "Forced split only flushes active segments")]
    public void ForcedSplit_FlushesOnlyWhenActive()
    {
        var seg = new EventSegmenter();
        var flushed = new List<EventSegmenter.Segment>();

        // No open segment yet.
        var idleForced = seg.FlushIfOpenAndAtLeastFrames(maxFrames: 5, flushedSegments: flushed);
        Assert.False(idleForced);
        Assert.Empty(flushed);

        // Active run should be flushable by max-frame split.
        for (var i = 0; i < 6; i++)
        {
            seg.OnFrame(frameIndex: i, hasEvent: true, flushedSegments: flushed);
        }

        var activeForced = seg.FlushIfOpenAndAtLeastFrames(maxFrames: 5, flushedSegments: flushed);
        Assert.True(activeForced);
        Assert.Single(flushed);
    }
}

