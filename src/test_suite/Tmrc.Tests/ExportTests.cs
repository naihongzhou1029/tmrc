using System;
using System.IO;
using Tmrc.Cli.Export;
using Tmrc.Core.Recall;
using Xunit;

namespace Tmrc.Tests;

public class ExportTests
{
    [Fact]
    public void GetDefaultExportPath_uses_cwd_session_and_range_in_filename()
    {
        var session = "default";
        var from = new DateTimeOffset(2025, 2, 20, 14, 30, 0, TimeSpan.Zero);
        var to = new DateTimeOffset(2025, 2, 20, 15, 0, 0, TimeSpan.Zero);
        var range = new TimeRange(from, to);

        var path = ExportPathHelper.GetDefaultExportPath(session, range, "mp4");

        var cwd = Directory.GetCurrentDirectory();
        Assert.StartsWith(cwd, path);
        Assert.EndsWith(".mp4", path);
        Assert.Contains("tmrc_export_default_", path);
        // Filename includes local-time stamps (yyyyMMdd_HHmmss_yyyyMMdd_HHmmss)
        var fileName = Path.GetFileName(path);
        Assert.Matches(@"tmrc_export_default_\d{8}_\d{6}_\d{8}_\d{6}\.mp4", fileName);
    }

    [Fact]
    public void GetDefaultExportPath_gif_and_manifest_extensions()
    {
        var range = new TimeRange(DateTimeOffset.UtcNow, DateTimeOffset.UtcNow.AddHours(1));

        Assert.EndsWith(".gif", ExportPathHelper.GetDefaultExportPath("s", range, "gif"));
        Assert.EndsWith(".manifest", ExportPathHelper.GetDefaultExportPath("s", range, "manifest"));
    }

    [Fact]
    public void GetDefaultExportPath_sanitizes_session_name()
    {
        var range = new TimeRange(DateTimeOffset.UtcNow, DateTimeOffset.UtcNow.AddMinutes(1));
        var path = ExportPathHelper.GetDefaultExportPath("work/session", range, "mp4");

        Assert.DoesNotContain("/", path);
        Assert.Contains("tmrc_export_", path);
    }
}
