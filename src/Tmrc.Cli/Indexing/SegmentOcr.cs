using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;

namespace Tmrc.Cli.Indexing;

/// <summary>
/// Runs OCR on the first frame of an MP4 segment: FFmpeg extracts frame to PNG, then Tesseract CLI returns text.
/// Optional: when Tesseract is not on PATH, Recognize returns null and ask continues to work without OCR text.
/// Supports configurable languages via locale list (BCP 47 / Apple-style); maps to Tesseract -l codes.
/// </summary>
public static class SegmentOcr
{
    /// <summary>Maps locale / BCP 47 style (e.g. en-US, zh-Hant) to Tesseract language codes for -l.</summary>
    private static readonly IReadOnlyDictionary<string, string> LocaleToTesseract = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
    {
        { "en", "eng" }, { "en-US", "eng" }, { "en-GB", "eng" },
        { "zh-Hant", "chi_tra" }, { "zh-TW", "chi_tra" },
        { "zh-Hans", "chi_sim" }, { "zh-CN", "chi_sim" },
        { "ja", "jpn" }, { "ja-JP", "jpn" },
        { "ko", "kor" }, { "ko-KR", "kor" },
    };
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
    /// <param name="localeLanguages">Optional: config ocr_recognition_languages (BCP 47 / locale). Mapped to Tesseract -l; when null/empty, Tesseract uses default.</param>
    /// </summary>
    public static string? Recognize(string mp4Path, IReadOnlyList<string>? localeLanguages = null)
    {
        if (!File.Exists(mp4Path) || !string.Equals(Path.GetExtension(mp4Path), ".mp4", StringComparison.OrdinalIgnoreCase))
        {
            return null;
        }

        if (!IsAvailable())
        {
            return null;
        }

        var langArg = BuildTesseractLangArg(localeLanguages);

        string? pngPath = null;
        try
        {
            pngPath = Path.Combine(Path.GetTempPath(), "tmrc_ocr_" + Guid.NewGuid().ToString("N")[..8] + ".png");

            var extractOk = RunFfmpegExtractFrame(mp4Path, pngPath);
            if (!extractOk || !File.Exists(pngPath))
            {
                return null;
            }

            return RunTesseract(pngPath, langArg);
        }
        finally
        {
            if (pngPath != null && File.Exists(pngPath))
            {
                try { File.Delete(pngPath); } catch { /* best-effort */ }
            }
        }
    }

    /// <summary>Builds Tesseract -l value from locale list (e.g. "eng+chi_tra"). Returns null to use Tesseract default.</summary>
    internal static string? BuildTesseractLangArg(IReadOnlyList<string>? localeLanguages)
    {
        if (localeLanguages is null || localeLanguages.Count == 0)
            return null;

        var codes = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var locale in localeLanguages)
        {
            if (string.IsNullOrWhiteSpace(locale)) continue;
            var trimmed = locale.Trim();
            if (LocaleToTesseract.TryGetValue(trimmed, out var code))
                codes.Add(code);
            else
                codes.Add(trimmed);
        }
        return codes.Count == 0 ? null : string.Join("+", codes.OrderBy(c => c, StringComparer.Ordinal));
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

    private static string? RunTesseract(string pngPath, string? langArg = null)
    {
        var outBase = Path.Combine(Path.GetTempPath(), "tmrc_tess_" + Guid.NewGuid().ToString("N")[..8]);
        var outTxt = outBase + ".txt";
        var psi = new ProcessStartInfo
        {
            FileName = TesseractExe,
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardError = true
        };
        psi.ArgumentList.Add(pngPath);
        psi.ArgumentList.Add(outBase);
        if (!string.IsNullOrEmpty(langArg))
        {
            psi.ArgumentList.Add("-l");
            psi.ArgumentList.Add(langArg);
        }

        try
        {
            using var process = Process.Start(psi);
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
