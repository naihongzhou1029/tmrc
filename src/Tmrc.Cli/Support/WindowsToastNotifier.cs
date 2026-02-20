using System;
using System.Diagnostics;
using System.IO;
using System.Text;
using Tmrc.Core.Support;

namespace Tmrc.Cli.Support;

/// <summary>
/// Shows Windows toast notifications via PowerShell and WinRT (Windows.UI.Notifications).
/// Falls back to stderr if PowerShell or WinRT fails.
/// </summary>
public sealed class WindowsToastNotifier : INotifier
{
    public void Toast(string title, string message)
    {
        if (TryShowToast(title, message))
            return;
        Console.Error.WriteLine($"[toast] {title}: {message}");
    }

    private static bool TryShowToast(string title, string message)
    {
        string? scriptPath = null;
        try
        {
            var sb = new StringBuilder();
            sb.AppendLine("param([string]$Title, [string]$Message)");
            sb.AppendLine("$ErrorActionPreference = 'Stop'");
            sb.AppendLine("function Esc-Xml { param([string]$t) $t -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;' -replace [char]39,'&apos;' -replace [char]34,'&quot;' }");
            sb.AppendLine("$t1 = Esc-Xml $Title");
            sb.AppendLine("$t2 = Esc-Xml $Message");
            sb.AppendLine("$null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]");
            sb.AppendLine("$xml = [Windows.Data.Xml.Dom.XmlDocument]::new()");
            sb.AppendLine("$xml.LoadXml(('<toast><visual><binding template=\"ToastText02\"><text id=\"1\">' + $t1 + '</text><text id=\"2\">' + $t2 + '</text></binding></visual></toast>'))");
            sb.AppendLine("[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('tmrc').Show([Windows.UI.Notifications.ToastNotification]::CreateToastNotification($xml))");

            scriptPath = Path.Combine(Path.GetTempPath(), "tmrc_toast_" + Guid.NewGuid().ToString("N")[..8] + ".ps1");
            File.WriteAllText(scriptPath, sb.ToString(), Encoding.UTF8);

            using var process = Process.Start(new ProcessStartInfo
            {
                FileName = "powershell.exe",
                ArgumentList = { "-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File", scriptPath, "-Title", title ?? "", "-Message", message ?? "" },
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardError = true,
                RedirectStandardOutput = true
            });
            if (process is null) return false;
            process.StandardOutput.ReadToEnd();
            process.StandardError.ReadToEnd();
            process.WaitForExit(5000);
            return process.ExitCode == 0;
        }
        catch
        {
            return false;
        }
        finally
        {
            if (scriptPath != null && File.Exists(scriptPath))
            {
                try { File.Delete(scriptPath); } catch { }
            }
        }
    }
}
