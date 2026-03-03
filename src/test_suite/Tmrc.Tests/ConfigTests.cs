using System.IO;
using Tmrc.Core.Config;
using Xunit;

namespace Tmrc.Tests;

public class ConfigTests
{
    [Fact(DisplayName = "Sample rate default when key missing")]
    public void SampleRateDefault()
    {
        var ini = "";
        var cfg = ConfigLoader.LoadFromIni(ini);
        Assert.Equal(100, cfg.SampleRateMs);
    }

    [Fact(DisplayName = "Sample rate override")]
    public void SampleRateOverride()
    {
        var ini = "sample_rate_ms = 16.1";
        var cfg = ConfigLoader.LoadFromIni(ini);
        Assert.Equal(16.1, cfg.SampleRateMs);
    }

    [Fact(DisplayName = "Sample rate 0 falls back to default")]
    public void SampleRateInvalid()
    {
        var ini = "sample_rate_ms = 0";
        var cfg = ConfigLoader.LoadFromIni(ini);
        Assert.Equal(100, cfg.SampleRateMs);
    }

    [Fact(DisplayName = "Session name default")]
    public void SessionDefault()
    {
        var cfg = ConfigLoader.LoadFromIni("");
        Assert.Equal("default", cfg.Session);
    }

    [Fact(DisplayName = "Session name from config")]
    public void SessionFromConfig()
    {
        var cfg = ConfigLoader.LoadFromIni("session = work");
        Assert.Equal("work", cfg.Session);
    }

    [Fact(DisplayName = "Capture mode default")]
    public void CaptureModeDefault()
    {
        var cfg = ConfigLoader.LoadFromIni("");
        Assert.Equal(CaptureMode.FullScreen, cfg.CaptureMode);
    }

    [Fact(DisplayName = "Display default")]
    public void DisplayDefault()
    {
        var cfg = ConfigLoader.LoadFromIni("");
        Assert.Equal(DisplaySelection.Main, cfg.Display);
    }

    [Fact(DisplayName = "Audio default")]
    public void AudioDefault()
    {
        var cfg = ConfigLoader.LoadFromIni("");
        Assert.False(cfg.AudioEnabled);
    }

    [Fact(DisplayName = "Audio enabled")]
    public void AudioEnabled()
    {
        var cfg = ConfigLoader.LoadFromIni("audio_enabled = true");
        Assert.True(cfg.AudioEnabled);
    }

    [Fact(DisplayName = "Lock/sleep default")]
    public void LockSleepDefault()
    {
        var cfg = ConfigLoader.LoadFromIni("");
        Assert.False(cfg.RecordWhenLockedOrSleeping);
    }

    [Fact(DisplayName = "Storage root default")]
    public void StorageRootDefault()
    {
        var cfg = ConfigLoader.LoadFromIni("");
        var expected = Path.Combine(
            System.Environment.GetFolderPath(System.Environment.SpecialFolder.UserProfile),
            ".tmrc");
        Assert.Equal(Path.GetFullPath(expected), Path.GetFullPath(cfg.StorageRoot));
    }

    [Fact(DisplayName = "Storage root override")]
    public void StorageRootOverride()
    {
        var cfg = ConfigLoader.LoadFromIni("storage_root = C:/tmp/tmrc-test");
        Assert.Equal("C:/tmp/tmrc-test", cfg.StorageRoot);
    }

    [Fact(DisplayName = "Index mode default")]
    public void IndexModeDefault()
    {
        var cfg = ConfigLoader.LoadFromIni("");
        Assert.Equal(IndexMode.Normal, cfg.IndexMode);
    }

    [Fact(DisplayName = "Index mode advanced and normal")]
    public void IndexModeValues()
    {
        var a = ConfigLoader.LoadFromIni("index_mode = advanced");
        Assert.Equal(IndexMode.Advanced, a.IndexMode);
        var n = ConfigLoader.LoadFromIni("index_mode = normal");
        Assert.Equal(IndexMode.Normal, n.IndexMode);
    }

    [Fact(DisplayName = "Invalid index mode throws")]
    public void IndexModeInvalid()
    {
        Assert.ThrowsAny<System.ArgumentException>(() =>
        {
            _ = ConfigLoader.LoadFromIni("index_mode = foo");
        });
    }

    [Fact(DisplayName = "OCR languages default")]
    public void OcrLanguagesDefault()
    {
        var cfg = ConfigLoader.LoadFromIni("");
        Assert.Equal(new[] { "en-US", "zh-Hant", "zh-Hans" }, cfg.OcrRecognitionLanguages);
    }

    [Fact(DisplayName = "OCR languages override")]
    public void OcrLanguagesOverride()
    {
        var ini = "ocr_recognition_languages = ja-JP,ko-KR";
        var cfg = ConfigLoader.LoadFromIni(ini);
        Assert.Equal(new[] { "ja-JP", "ko-KR" }, cfg.OcrRecognitionLanguages);
    }

    [Fact(DisplayName = "Retention defaults (30 days, 50 GB)")]
    public void RetentionDefaults()
    {
        var cfg = ConfigLoader.LoadFromIni("");
        Assert.Equal(30, cfg.RetentionMaxAgeDays);
        Assert.Equal(50L * 1024 * 1024 * 1024, cfg.RetentionMaxDiskBytes);
    }

    [Fact(DisplayName = "Retention override from config")]
    public void RetentionOverride()
    {
        var cfg = ConfigLoader.LoadFromIni("retention_max_age_days = 14\nretention_max_disk_bytes = 1000000000");
        Assert.Equal(14, cfg.RetentionMaxAgeDays);
        Assert.Equal(1_000_000_000L, cfg.RetentionMaxDiskBytes);
    }

    [Fact(DisplayName = "Retention zero disables limit")]
    public void RetentionZeroAllowed()
    {
        var cfg = ConfigLoader.LoadFromIni("retention_max_age_days = 0\nretention_max_disk_bytes = 0");
        Assert.Equal(0, cfg.RetentionMaxAgeDays);
        Assert.Equal(0L, cfg.RetentionMaxDiskBytes);
    }
}
