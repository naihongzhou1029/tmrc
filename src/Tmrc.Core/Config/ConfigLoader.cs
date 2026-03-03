using System;
using System.IO;
using System.Linq;
using System.Collections.Generic;

namespace Tmrc.Core.Config;

public enum ConfigError
{
    InvalidSampleRate,
    InvalidIndexMode
}

public static class ConfigLoader
{
    public static TmrcConfig LoadFromFile(string path)
    {
        var ini = File.Exists(path) ? File.ReadAllText(path) : string.Empty;
        return LoadFromIni(ini);
    }

    public static TmrcConfig LoadFromIni(string ini)
    {
        if (string.IsNullOrWhiteSpace(ini))
        {
            return Normalize(new TmrcConfig());
        }

        var pairs = ParseIni(ini);
        var builder = new TmrcConfig();

        foreach (var (key, value) in pairs)
        {
            switch (key)
            {
                case "sample_rate_ms":
                    if (double.TryParse(value, out var sr))
                        builder = builder with { SampleRateMs = sr };
                    break;
                case "segment_max_duration_ms":
                    if (int.TryParse(value, out var segDur) && segDur > 0)
                        builder = builder with { SegmentMaxDurationMs = segDur };
                    break;
                case "capture_diff_threshold":
                    if (int.TryParse(value, out var diffThreshold) && diffThreshold >= 0)
                        builder = builder with { CaptureDiffThreshold = diffThreshold };
                    break;
                case "session":
                    if (!string.IsNullOrWhiteSpace(value))
                        builder = builder with { Session = value };
                    break;
                case "capture_mode":
                    if (!string.IsNullOrWhiteSpace(value))
                        builder = builder with
                        {
                            CaptureMode = value switch
                            {
                                "full_screen" => CaptureMode.FullScreen,
                                "window" => CaptureMode.Window,
                                "app" => CaptureMode.App,
                                _ => CaptureMode.FullScreen
                            }
                        };
                    break;
                case "display":
                    if (!string.IsNullOrWhiteSpace(value))
                        builder = builder with
                        {
                            Display = value == "main" ? DisplaySelection.Main : DisplaySelection.Index
                        };
                    break;
                case "audio_enabled":
                    if (bool.TryParse(value, out var audio))
                        builder = builder with { AudioEnabled = audio };
                    break;
                case "record_when_locked_or_sleeping":
                    if (bool.TryParse(value, out var rl))
                        builder = builder with { RecordWhenLockedOrSleeping = rl };
                    break;
                case "storage_root":
                    if (!string.IsNullOrWhiteSpace(value))
                    {
                        var expanded = value.StartsWith("~")
                            ? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
                                value.TrimStart('~').TrimStart('/', '\\'))
                            : value;
                        builder = builder with { StorageRoot = expanded };
                    }
                    break;
                case "index_mode":
                    if (!string.IsNullOrWhiteSpace(value))
                        builder = builder with
                        {
                            IndexMode = value switch
                            {
                                "normal" => IndexMode.Normal,
                                "advanced" => IndexMode.Advanced,
                                _ => throw new ArgumentException("Invalid index_mode", nameof(ini))
                            }
                        };
                    break;
                case "ocr_recognition_languages":
                    if (!string.IsNullOrWhiteSpace(value))
                    {
                        var langs = value.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
                        if (langs.Length > 0)
                            builder = builder with { OcrRecognitionLanguages = langs };
                    }
                    break;
                case "retention_max_age_days":
                    if (int.TryParse(value, out var maxAge) && maxAge >= 0)
                        builder = builder with { RetentionMaxAgeDays = maxAge };
                    break;
                case "retention_max_disk_bytes":
                    if (long.TryParse(value, out var maxDisk) && maxDisk >= 0)
                        builder = builder with { RetentionMaxDiskBytes = maxDisk };
                    break;
            }
        }

        return Normalize(builder);
    }

    private static Dictionary<string, string> ParseIni(string ini)
    {
        var result = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var rawLine in ini.Split('\n'))
        {
            var line = rawLine.Trim();
            if (string.IsNullOrEmpty(line) || line[0] == '#' || line[0] == ';' || line[0] == '[')
                continue;
            var eq = line.IndexOf('=');
            if (eq <= 0) continue;
            var key = line[..eq].Trim();
            var value = line[(eq + 1)..].Trim();
            if (!string.IsNullOrEmpty(key))
                result[key] = value;
        }
        return result;
    }

    private static TmrcConfig Normalize(TmrcConfig cfg)
    {
        if (cfg.SampleRateMs <= 0)
        {
            cfg = cfg with { SampleRateMs = 100 };
        }
        if (cfg.SegmentMaxDurationMs <= 0)
        {
            cfg = cfg with { SegmentMaxDurationMs = 1000 };
        }
        if (cfg.CaptureDiffThreshold < 0)
        {
            cfg = cfg with { CaptureDiffThreshold = 100_000 };
        }

        if (string.IsNullOrWhiteSpace(cfg.Session))
        {
            cfg = cfg with { Session = "default" };
        }

        if (string.IsNullOrWhiteSpace(cfg.StorageRoot))
        {
            cfg = cfg with
            {
                StorageRoot = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
                    ".tmrc")
            };
        }

        if (cfg.OcrRecognitionLanguages is null || !cfg.OcrRecognitionLanguages.Any())
        {
            cfg = cfg with
            {
                OcrRecognitionLanguages = new[] { "en-US", "zh-Hant", "zh-Hans" }
            };
        }

        if (cfg.RetentionMaxAgeDays < 0)
            cfg = cfg with { RetentionMaxAgeDays = 30 };
        if (cfg.RetentionMaxDiskBytes < 0)
            cfg = cfg with { RetentionMaxDiskBytes = 50L * 1024 * 1024 * 1024 };

        return cfg;
    }
}
