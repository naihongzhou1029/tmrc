using System;
using System.Collections.Generic;

namespace Tmrc.Core.Recording;

/// <summary>
/// Event-based segmenter that groups "active" frames into segments and
/// flushes a segment when an idle frame (no events) is seen after activity.
/// This models the semantics described in the spec for items 1.1–1.2.
/// </summary>
public sealed class EventSegmenter
{
    public readonly record struct Segment(int StartFrame, int EndFrame);

    private readonly int _minFramesPerSegment;

    private bool _hasOpenSegment;
    private int _currentStartFrame;
    private int _lastEventFrame;

    public EventSegmenter(int minFramesPerSegment = 1)
    {
        if (minFramesPerSegment <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(minFramesPerSegment));
        }

        _minFramesPerSegment = minFramesPerSegment;
    }

    /// <summary>
    /// Feed a single frame into the segmenter.
    /// <paramref name="frameIndex"/> is a monotonically increasing index (e.g. 0,1,2,...).
    /// <paramref name="hasEvent"/> indicates whether this frame contains any events.
    /// When an idle frame follows an active run, a segment is flushed.
    /// </summary>
    public void OnFrame(int frameIndex, bool hasEvent, IList<Segment> flushedSegments)
    {
        if (flushedSegments is null) throw new ArgumentNullException(nameof(flushedSegments));

        if (hasEvent)
        {
            if (!_hasOpenSegment)
            {
                _hasOpenSegment = true;
                _currentStartFrame = frameIndex;
            }

            _lastEventFrame = frameIndex;
            return;
        }

        // Idle frame: if we had an open segment, flush it.
        if (_hasOpenSegment)
        {
            FlushCurrentSegment(flushedSegments);
        }
    }

    /// <summary>
    /// Flush any open segment at the end of the stream (e.g. end-of-recording).
    /// </summary>
    public void FlushTail(IList<Segment> flushedSegments)
    {
        if (flushedSegments is null) throw new ArgumentNullException(nameof(flushedSegments));
        if (_hasOpenSegment)
        {
            FlushCurrentSegment(flushedSegments);
        }
    }

    private void FlushCurrentSegment(IList<Segment> flushedSegments)
    {
        var length = _lastEventFrame - _currentStartFrame + 1;
        if (length < _minFramesPerSegment)
        {
            // Enforce minimum size by extending end frame; spec guarantees at least one
            // sample-interval clip per event.
            var adjustedEnd = _currentStartFrame + _minFramesPerSegment - 1;
            flushedSegments.Add(new Segment(_currentStartFrame, adjustedEnd));
        }
        else
        {
            flushedSegments.Add(new Segment(_currentStartFrame, _lastEventFrame));
        }

        _hasOpenSegment = false;
    }
}

