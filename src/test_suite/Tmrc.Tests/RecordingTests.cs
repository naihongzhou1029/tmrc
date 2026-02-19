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
}

