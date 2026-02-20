using System.IO;
using Tmrc.Cli.Indexing;
using Xunit;

namespace Tmrc.Tests;

public class OcrTests
{
    [Fact(DisplayName = "Recognize returns null for non-existent path")]
    public void Recognize_NonExistentPath_ReturnsNull()
    {
        var path = Path.Combine(Path.GetTempPath(), "tmrc-nonexistent-" + System.Guid.NewGuid().ToString("N") + ".mp4");
        var result = SegmentOcr.Recognize(path);
        Assert.Null(result);
    }

    [Fact(DisplayName = "Recognize returns null for non-MP4 extension")]
    public void Recognize_NonMp4Extension_ReturnsNull()
    {
        var path = Path.Combine(Path.GetTempPath(), "file.bin");
        var result = SegmentOcr.Recognize(path);
        Assert.Null(result);
    }
}
