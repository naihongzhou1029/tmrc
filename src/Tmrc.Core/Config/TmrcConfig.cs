using System;
using System.Collections.Generic;

namespace Tmrc.Core.Config;

public enum CaptureMode
{
    FullScreen,
    Window,
    App
}

public enum DisplaySelection
{
    Main,
    Index
}

public enum IndexMode
{
    Normal,
    Advanced
}

public enum ExportQuality
{
    Low,
    Medium,
    High
}

public sealed record class TmrcConfig
{
    public double SampleRateMs { get; init; } = 100;
    public int SegmentMaxDurationMs { get; init; } = 1000;
    public int CaptureDiffThreshold { get; init; } = 100_000;

    public string Session { get; init; } = "default";

    public CaptureMode CaptureMode { get; init; } = CaptureMode.FullScreen;

    public DisplaySelection Display { get; init; } = DisplaySelection.Main;

    public bool AudioEnabled { get; init; }

    public bool RecordWhenLockedOrSleeping { get; init; }

    public string StorageRoot { get; init; } =
        System.IO.Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            ".tmrc");

    public IndexMode IndexMode { get; init; } = IndexMode.Normal;

    public IReadOnlyList<string> OcrRecognitionLanguages { get; init; } =
        new[] { "en-US", "zh-Hant", "zh-Hans" };

    public string SearchDefaultRange { get; init; } = "24h";

    public ExportQuality ExportQuality { get; init; } = ExportQuality.High;

    public string LogLevel { get; init; } = "info";

    /// <summary>Max segment age in days; evict older. Default 30. Set to 0 to disable age-based eviction.</summary>
    public int RetentionMaxAgeDays { get; init; } = 30;

    /// <summary>Max disk usage in bytes for segments; evict oldest when over. Default 50 GB. Set to 0 to disable.</summary>
    public long RetentionMaxDiskBytes { get; init; } = 50L * 1024 * 1024 * 1024;

    public string? LlmProvider { get; init; }
    public string? LlmModel { get; init; }
}

