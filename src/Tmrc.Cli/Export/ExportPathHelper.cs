using System;
using System.IO;
using Tmrc.Core.Recall;

namespace Tmrc.Cli.Export;

/// <summary>Default export path when -o is omitted (spec Export 6): cwd, session and time range in filename.</summary>
internal static class ExportPathHelper
{
    public static string GetDefaultExportPath(string session, TimeRange range, string format)
    {
        var invalid = Path.GetInvalidFileNameChars();
        var safeSession = string.IsNullOrWhiteSpace(session)
            ? "default"
            : string.Join("_", session.Split(invalid, StringSplitOptions.RemoveEmptyEntries));
        if (string.IsNullOrEmpty(safeSession))
            safeSession = "default";
        var fromLocal = range.From.ToLocalTime();
        var toLocal = range.To.ToLocalTime();
        var ext = format switch
        {
            "gif" => ".gif",
            "manifest" => ".manifest",
            _ => ".mp4"
        };
        var fileName = $"tmrc_export_{safeSession}_{fromLocal:yyyyMMdd_HHmmss}_{toLocal:yyyyMMdd_HHmmss}{ext}";
        return Path.Combine(Directory.GetCurrentDirectory(), fileName);
    }
}
