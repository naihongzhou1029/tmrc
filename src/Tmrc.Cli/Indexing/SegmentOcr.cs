using System;
using System.Diagnostics;
using System.IO;

namespace Tmrc.Cli.Indexing;

/// <summary>
/// Runs OCR on the first frame of an MP4 segment: FFmpeg extracts frame to PNG, then Tesseract CLI returns text.
/// Optional: when Tesseract is not on PATH, Recognize returns null and ask continues to work without OCR text.
/// </summary>
public static class SegmentOcr
{
    private const string FfmpegExe = "ffmpeg";
    private const string TesseractExe = "tesseract";

    public static bool IsAvailable()
    {
        if (!FfmpegAvailable())
        {
            return false;
        }

        try
        {
            using var process = Process.Start(new ProcessStartInfo
            {
                FileName = TesseractExe,
                ArgumentList = { "--version" },
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
    /// Extracts first frame from the MP4, runs Tesseract, returns recognized text or null on failure/unavailable.
    /// </summary>
    public static string? Recognize(string mp4Path)
    {
        if (!File.Exists(mp4Path) || !string.Equals(Path.GetExtension(mp4Path), ".mp4", StringComparison.OrdinalIgnoreCase))
        {
            return null;
        }

        if (!IsAvailable())
        {
            return null;
        }

        string? pngPath = null;
        try
        {
            pngPath = Path.Combine(Path.GetTempPath(), "tmrc_ocr_" + Guid.NewGuid().ToString("N")[..8] + ".png");

            var extractOk = RunFfmpegExtractFrame(mp4Path, pngPath);
            if (!extractOk || !File.Exists(pngPath))
            {
                return null;
            }

            return RunTesseract(pngPath);
        }
        finally
        {
            if (pngPath != null && File.Exists(pngPath))
            {
                try { File.Delete(pngPath); } catch { /* best-effort */ }
            }
        }
    }

    private static bool FfmpegAvailable()
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

    private static bool RunFfmpegExtractFrame(string mp4Path, string pngPath)
    {
        try
        {
            using var process = Process.Start(new ProcessStartInfo
            {
                FileName = FfmpegExe,
                ArgumentList = { "-y", "-i", mp4Path, "-vframes", "1", "-f", "image2", pngPath },
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            });
            if (process is null) return false;
            process.StandardOutput.ReadToEnd();
            process.StandardError.ReadToEnd();
            process.WaitForExit(15_000);
            return process.ExitCode == 0;
        }
        catch
        {
            return false;
        }
    }

    private static string? RunTesseract(string pngPath)
    {
        // Tesseract writes to <outputbase>.txt; use a temp file and read it.
        var outBase = Path.Combine(Path.GetTempPath(), "tmrc_tess_" + Guid.NewGuid().ToString("N")[..8]);
        var outTxt = outBase + ".txt";
        try
        {
            using var process = Process.Start(new ProcessStartInfo
            {
                FileName = TesseractExe,
                ArgumentList = { pngPath, outBase },
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardError = true
            });
            if (process is null) return null;

            process.StandardError.ReadToEnd();
            process.WaitForExit(10_000);

            if (process.ExitCode != 0 || !File.Exists(outTxt))
            {
                return null;
            }

            var text = File.ReadAllText(outTxt).Trim();
            return text.Length > 0 ? text : null;
        }
        finally
        {
            if (File.Exists(outTxt))
            {
                try { File.Delete(outTxt); } catch { /* best-effort */ }
            }
        }
    }
}
