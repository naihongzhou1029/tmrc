using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Threading;
using Tmrc.Core.Config;

namespace Tmrc.Cli.Export;

/// <summary>
/// Stitches segment MP4s into a single MP4 or GIF using FFmpeg (concat demuxer + optional re-encode).
/// </summary>
public static class VideoExport
{
    private const string FfmpegExe = "ffmpeg";

    public static bool IsAvailable()
    {
        try
        {
            using var process = Process.Start(new ProcessStartInfo
            {
                FileName = FfmpegExe,
                ArgumentList = { "-version" },
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            });
            process?.WaitForExit(2000);
            return process?.ExitCode == 0;
        }
        catch
        {
            return false;
        }
    }

    /// <summary>
    /// Stitches MP4 segments into one MP4. Fails if any path is not .mp4 or FFmpeg is unavailable.
    /// </summary>
    public static bool StitchToMp4(
        IReadOnlyList<string> segmentPaths,
        string outputPath,
        ExportQuality quality)
    {
        if (segmentPaths.Count == 0)
        {
            return false;
        }

        foreach (var p in segmentPaths)
        {
            if (!string.Equals(Path.GetExtension(p), ".mp4", StringComparison.OrdinalIgnoreCase))
            {
                return false;
            }
        }

        string? listPath = null;
        try
        {
            listPath = Path.Combine(Path.GetTempPath(), "tmrc_concat_" + Guid.NewGuid().ToString("N")[..8] + ".txt");
            WriteConcatList(listPath, segmentPaths);

            var qualityArgs = GetMp4QualityArgs(quality);
            var args = new List<string>
            {
                "-y",
                "-f", "concat",
                "-safe", "0",
                "-i", listPath,
                "-c:v", "libx264",
                "-pix_fmt", "yuv420p"
            };
            args.AddRange(qualityArgs);
            args.Add("-progress");
            args.Add("pipe:1");
            args.Add("-nostats");
            args.Add(outputPath);

            return RunFfmpeg(args, timeoutMs: Timeout.Infinite);
        }
        finally
        {
            if (listPath != null && File.Exists(listPath))
            {
                try { File.Delete(listPath); } catch { /* best-effort */ }
            }
        }
    }

    /// <summary>
    /// Stitches MP4 segments into one GIF via temp MP4 then palette conversion.
    /// </summary>
    public static bool StitchToGif(
        IReadOnlyList<string> segmentPaths,
        string outputPath,
        ExportQuality quality)
    {
        if (segmentPaths.Count == 0)
        {
            return false;
        }

        string? tempMp4 = null;
        try
        {
            tempMp4 = Path.Combine(Path.GetTempPath(), "tmrc_gif_" + Guid.NewGuid().ToString("N")[..8] + ".mp4");
            if (!StitchToMp4(segmentPaths, tempMp4, quality))
            {
                return false;
            }

            // GIF: scale and fps from quality; palettegen + paletteuse for decent color.
            var (scale, fps) = GetGifScaleAndFps(quality);
            var filter = $"fps={fps},scale={scale}:flags=lanczos,split[s0][s1];[s0]palettegen=maxcolors=256[p];[s1][p]paletteuse=dither=bayer";
            var args = new List<string>
            {
                "-y",
                "-i", tempMp4,
                "-vf", filter,
                "-loop", "0",
                "-progress", "pipe:1",
                "-nostats",
                outputPath
            };
            return RunFfmpeg(args, timeoutMs: Timeout.Infinite);
        }
        finally
        {
            if (tempMp4 != null && File.Exists(tempMp4))
            {
                try { File.Delete(tempMp4); } catch { /* best-effort */ }
            }
        }
    }

    private static void WriteConcatList(string listPath, IReadOnlyList<string> segmentPaths)
    {
        // FFmpeg concat demuxer expects plain "file ..." at byte 0.
        // Avoid UTF-8 BOM, which can make the first token appear as "﻿file".
        using var writer = new StreamWriter(listPath, false, new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
        foreach (var p in segmentPaths)
        {
            var escaped = p.Replace("'", "''", StringComparison.Ordinal);
            writer.WriteLine("file '" + escaped + "'");
        }
    }

    private static List<string> GetMp4QualityArgs(ExportQuality quality)
    {
        return quality switch
        {
            ExportQuality.Low => new List<string> { "-vf", "scale=-2:720", "-b:v", "2M", "-maxrate", "2M" },
            ExportQuality.Medium => new List<string> { "-vf", "scale=-2:1080", "-b:v", "5M", "-maxrate", "5M" },
            _ => new List<string> { "-b:v", "8M", "-maxrate", "8M" }
        };
    }

    private static (string scale, int fps) GetGifScaleAndFps(ExportQuality quality)
    {
        return quality switch
        {
            ExportQuality.Low => ("480:-1", 8),
            ExportQuality.Medium => ("640:-1", 10),
            _ => ("800:-1", 10)
        };
    }

    private static bool RunFfmpeg(List<string> args, int timeoutMs)
    {
        try
        {
            var startInfo = new ProcessStartInfo
            {
                FileName = FfmpegExe,
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            };
            foreach (var a in args)
            {
                startInfo.ArgumentList.Add(a);
            }

            using var process = Process.Start(startInfo);
            if (process is null)
            {
                return false;
            }

            var stdOut = new StringBuilder();
            var stdErr = new StringBuilder();
            var progressLock = new object();
            var nextProgressAt = DateTime.UtcNow;
            string? progressTime = null;
            string? progressSpeed = null;
            string? progressFps = null;
            string? progressFrame = null;
            process.OutputDataReceived += (_, e) =>
            {
                if (e.Data is not null)
                {
                    if (TryParseProgressLine(e.Data, out var key, out var value))
                    {
                        lock (progressLock)
                        {
                            switch (key)
                            {
                                case "out_time":
                                    progressTime = value;
                                    break;
                                case "speed":
                                    progressSpeed = value;
                                    break;
                                case "fps":
                                    progressFps = value;
                                    break;
                                case "frame":
                                    progressFrame = value;
                                    break;
                                case "progress":
                                    if (value == "continue")
                                    {
                                        EmitProgress(false);
                                    }
                                    else if (value == "end")
                                    {
                                        EmitProgress(true);
                                    }
                                    break;
                            }
                        }
                    }
                    else
                    {
                        stdOut.AppendLine(e.Data);
                    }
                }
            };
            process.ErrorDataReceived += (_, e) =>
            {
                if (e.Data is not null)
                {
                    stdErr.AppendLine(e.Data);
                }
            };

            void EmitProgress(bool force)
            {
                if (!force && DateTime.UtcNow < nextProgressAt)
                {
                    return;
                }

                if (string.IsNullOrWhiteSpace(progressTime) &&
                    string.IsNullOrWhiteSpace(progressSpeed) &&
                    string.IsNullOrWhiteSpace(progressFrame))
                {
                    return;
                }

                var parts = new List<string>();
                if (!string.IsNullOrWhiteSpace(progressTime))
                {
                    parts.Add($"time={progressTime}");
                }
                if (!string.IsNullOrWhiteSpace(progressFrame))
                {
                    parts.Add($"frame={progressFrame}");
                }
                if (!string.IsNullOrWhiteSpace(progressFps))
                {
                    parts.Add($"fps={progressFps}");
                }
                if (!string.IsNullOrWhiteSpace(progressSpeed))
                {
                    parts.Add($"speed={progressSpeed}");
                }

                Console.WriteLine("[ffmpeg] " + string.Join(" ", parts));
                nextProgressAt = DateTime.UtcNow.AddSeconds(2);
            }

            static bool TryParseProgressLine(string line, out string key, out string value)
            {
                var idx = line.IndexOf('=');
                if (idx <= 0 || idx >= line.Length - 1)
                {
                    key = string.Empty;
                    value = string.Empty;
                    return false;
                }

                key = line[..idx];
                value = line[(idx + 1)..];
                return true;
            }

            process.BeginOutputReadLine();
            process.BeginErrorReadLine();

            if (!process.WaitForExit(timeoutMs))
            {
                try
                {
                    process.Kill(entireProcessTree: true);
                }
                catch
                {
                    // best-effort
                }

                var timeoutText = timeoutMs == Timeout.Infinite ? "infinite timeout" : $"{timeoutMs} ms";
                Console.Error.WriteLine($"FFmpeg timed out after {timeoutText}.");
                return false;
            }

            // Ensure async stream handlers have flushed.
            process.WaitForExit();

            if (process.ExitCode != 0)
            {
                var outText = stdOut.ToString();
                var errText = stdErr.ToString();
                var detail = string.IsNullOrWhiteSpace(errText) ? outText : errText;
                if (!string.IsNullOrWhiteSpace(detail))
                {
                    Console.Error.WriteLine(detail.Trim());
                }
                return false;
            }

            return true;
        }
        catch
        {
            return false;
        }
    }
}
