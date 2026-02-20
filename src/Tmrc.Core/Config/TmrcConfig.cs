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

    public string AskDefaultRange { get; init; } = "24h";

    public ExportQuality ExportQuality { get; init; } = ExportQuality.High;

    public string LogLevel { get; init; } = "info";
}

