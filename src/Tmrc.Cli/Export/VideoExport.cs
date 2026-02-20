using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text;
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
            args.Add(outputPath);

            return RunFfmpeg(args);
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
                outputPath
            };
            return RunFfmpeg(args);
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
        using var writer = new StreamWriter(listPath, false, Encoding.UTF8);
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

    private static bool RunFfmpeg(List<string> args)
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

            process.StandardOutput.ReadToEnd();
            process.StandardError.ReadToEnd();
            process.WaitForExit(120_000);
            return process.ExitCode == 0;
        }
        catch
        {
            return false;
        }
    }
}
