using System;
using System.IO;
using System.Linq;
using System.Collections.Generic;
using YamlDotNet.RepresentationModel;

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
        var yaml = File.Exists(path) ? File.ReadAllText(path) : string.Empty;
        return LoadFromYaml(yaml);
    }

    public static TmrcConfig LoadFromYaml(string yaml)
    {
        if (string.IsNullOrWhiteSpace(yaml))
        {
            return Normalize(new TmrcConfig());
        }

        var stream = new YamlStream();
        using var reader = new StringReader(yaml);
        stream.Load(reader);

        if (stream.Documents.Count == 0 || stream.Documents[0].RootNode is not YamlMappingNode root)
        {
            return Normalize(new TmrcConfig());
        }

        var builder = new TmrcConfig();

        foreach (var entry in root.Children)
        {
            if (entry.Key is not YamlScalarNode keyNode) continue;
            var key = keyNode.Value ?? string.Empty;
            switch (key)
            {
                case "sample_rate_ms":
                    if (entry.Value is YamlScalarNode srNode &&
                        double.TryParse(srNode.Value, out var sr))
                    {
                        builder = builder with { SampleRateMs = sr };
                    }
                    break;
                case "session":
                    if (entry.Value is YamlScalarNode sNode && !string.IsNullOrWhiteSpace(sNode.Value))
                    {
                        builder = builder with { Session = sNode.Value! };
                    }
                    break;
                case "capture_mode":
                    if (entry.Value is YamlScalarNode cNode && !string.IsNullOrWhiteSpace(cNode.Value))
                    {
                        var v = cNode.Value!;
                        builder = builder with
                        {
                            CaptureMode = v switch
                            {
                                "full_screen" => CaptureMode.FullScreen,
                                "window" => CaptureMode.Window,
                                "app" => CaptureMode.App,
                                _ => CaptureMode.FullScreen
                            }
                        };
                    }
                    break;
                case "display":
                    if (entry.Value is YamlScalarNode dNode && !string.IsNullOrWhiteSpace(dNode.Value))
                    {
                        var v = dNode.Value!;
                        builder = builder with
                        {
                            Display = v == "main" ? DisplaySelection.Main : DisplaySelection.Index
                        };
                    }
                    break;
                case "audio_enabled":
                    if (entry.Value is YamlScalarNode aNode &&
                        bool.TryParse(aNode.Value, out var audio))
                    {
                        builder = builder with { AudioEnabled = audio };
                    }
                    break;
                case "record_when_locked_or_sleeping":
                    if (entry.Value is YamlScalarNode lNode &&
                        bool.TryParse(lNode.Value, out var rl))
                    {
                        builder = builder with { RecordWhenLockedOrSleeping = rl };
                    }
                    break;
                case "storage_root":
                    if (entry.Value is YamlScalarNode rNode && !string.IsNullOrWhiteSpace(rNode.Value))
                    {
                        var raw = rNode.Value!;
                        var expanded = raw.StartsWith("~")
                            ? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
                                raw.TrimStart('~').TrimStart('/', '\\'))
                            : raw;
                        builder = builder with { StorageRoot = expanded };
                    }
                    break;
                case "index_mode":
                    if (entry.Value is YamlScalarNode imNode && !string.IsNullOrWhiteSpace(imNode.Value))
                    {
                        var v = imNode.Value!;
                        builder = builder with
                        {
                            IndexMode = v switch
                            {
                                "normal" => IndexMode.Normal,
                                "advanced" => IndexMode.Advanced,
                                _ => throw new ArgumentException("Invalid index_mode", nameof(yaml))
                            }
                        };
                    }
                    break;
                case "ocr_recognition_languages":
                    if (entry.Value is YamlSequenceNode seq)
                    {
                        var langs = seq.Children
                            .OfType<YamlScalarNode>()
                            .Select(n => n.Value)
                            .Where(v => !string.IsNullOrWhiteSpace(v))
                            .Cast<string>()
                            .ToArray();
                        if (langs.Length > 0)
                        {
                            builder = builder with { OcrRecognitionLanguages = langs };
                        }
                    }
                    break;
                case "retention_max_age_days":
                    if (entry.Value is YamlScalarNode ageNode &&
                        int.TryParse(ageNode.Value, out var maxAge) && maxAge >= 0)
                    {
                        builder = builder with { RetentionMaxAgeDays = maxAge };
                    }
                    break;
                case "retention_max_disk_bytes":
                    if (entry.Value is YamlScalarNode diskNode &&
                        long.TryParse(diskNode.Value, out var maxDisk) && maxDisk >= 0)
                    {
                        builder = builder with { RetentionMaxDiskBytes = maxDisk };
                    }
                    break;
            }
        }

        return Normalize(builder);
    }

    private static TmrcConfig Normalize(TmrcConfig cfg)
    {
        if (cfg.SampleRateMs <= 0)
        {
            // align with Swift tests: either default or validation error.
            cfg = cfg with { SampleRateMs = 100 };
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

