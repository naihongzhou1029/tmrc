using Tmrc.Cli.Capture;
using Xunit;

namespace Tmrc.Tests;

public class ScreenCaptureTests
{
    [Fact(DisplayName = "Identical frames should not trigger event")]
    public void IdenticalFrames_NoEvent()
    {
        var sc = new ScreenCapture(diffThreshold: 500_000, width: 100, height: 100);
        var buffer = new byte[100 * 100 * 4];
        for (int i = 0; i < buffer.Length; i++) buffer[i] = 128;

        sc.SetPreviousForTest(buffer);
        bool hasEvent = sc.ComputeHasEvent(buffer);

        Assert.False(hasEvent);
    }

    [Fact(DisplayName = "Alpha-only changes should not trigger event")]
    public void AlphaOnlyChanges_NoEvent()
    {
        var sc = new ScreenCapture(diffThreshold: 500_000, width: 100, height: 100);
        var prev = new byte[100 * 100 * 4];
        var curr = new byte[100 * 100 * 4];
        
        for (int i = 0; i < prev.Length; i += 4)
        {
            prev[i] = prev[i+1] = prev[i+2] = 128;
            prev[i+3] = 255; // Alpha

            curr[i] = curr[i+1] = curr[i+2] = 128;
            curr[i+3] = 0;   // Alpha changed
        }

        sc.SetPreviousForTest(prev);
        bool hasEvent = sc.ComputeHasEvent(curr);

        Assert.False(hasEvent);
    }

    [Fact(DisplayName = "Small BGR changes below threshold should not trigger event")]
    public void SmallChanges_BelowThreshold_NoEvent()
    {
        // 100x100 = 10,000 pixels.
        // If we change 100 pixels by 10 units in one channel, total diff is 1,000.
        // Threshold is 500,000.
        var sc = new ScreenCapture(diffThreshold: 500_000, width: 100, height: 100);
        var prev = new byte[100 * 100 * 4];
        var curr = new byte[100 * 100 * 4];

        sc.SetPreviousForTest(prev);
        
        // Change some pixels slightly
        for (int i = 0; i < 400; i += 4) // First 100 pixels
        {
            curr[i] = 10; 
        }

        bool hasEvent = sc.ComputeHasEvent(curr);
        Assert.False(hasEvent);
    }

    [Fact(DisplayName = "Large BGR changes above threshold should trigger event")]
    public void LargeChanges_AboveThreshold_HasEvent()
    {
        // 100x100 = 10,000 pixels.
        // Change all pixels by 60 units in one channel. Total diff = 10,000 * 60 = 600,000.
        // Threshold is 500,000.
        var sc = new ScreenCapture(diffThreshold: 500_000, width: 100, height: 100);
        var prev = new byte[100 * 100 * 4];
        var curr = new byte[100 * 100 * 4];

        for (int i = 0; i < curr.Length; i += 4)
        {
            curr[i] = 60;
        }

        sc.SetPreviousForTest(prev);
        bool hasEvent = sc.ComputeHasEvent(curr);

        Assert.True(hasEvent);
    }
}
