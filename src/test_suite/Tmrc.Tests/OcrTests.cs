using System.Collections.Generic;
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

    [Fact(DisplayName = "BuildTesseractLangArg maps locales and deduplicates")]
    public void BuildTesseractLangArg_MapsLocalesAndDeduplicates()
    {
        Assert.Null(SegmentOcr.BuildTesseractLangArg(null));
        Assert.Null(SegmentOcr.BuildTesseractLangArg(new List<string>()));

        var one = SegmentOcr.BuildTesseractLangArg(new[] { "en-US" });
        Assert.Equal("eng", one);

        var multi = SegmentOcr.BuildTesseractLangArg(new[] { "zh-Hant", "en-US", "zh-Hans" });
        Assert.NotNull(multi);
        var parts = multi!.Split('+');
        Assert.Equal(3, parts.Length);
        Assert.Contains("chi_tra", parts);
        Assert.Contains("chi_sim", parts);
        Assert.Contains("eng", parts);

        var unknownPassThrough = SegmentOcr.BuildTesseractLangArg(new[] { "custom_code" });
        Assert.Equal("custom_code", unknownPassThrough);
    }
}
