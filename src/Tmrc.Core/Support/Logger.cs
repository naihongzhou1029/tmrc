using System;
using System.IO;

namespace Tmrc.Core.Support;

public enum LogLevel
{
    Debug,
    Info,
    Warn,
    Error
}

public sealed class Logger
{
    private readonly string _logFilePath;
    private readonly LogLevel _level;

    private const int RotationRetentionDays = 7;

    public Logger(string logFilePath, LogLevel level)
    {
        _logFilePath = logFilePath;
        _level = level;
        RotateIfOld();
    }

    /// <summary>Single-file rotation: if log file exists and is older than 7 days, truncate it.</summary>
    private void RotateIfOld()
    {
        try
        {
            if (!File.Exists(_logFilePath))
                return;
            var lastWrite = File.GetLastWriteTimeUtc(_logFilePath);
            if ((DateTime.UtcNow - lastWrite).TotalDays < RotationRetentionDays)
                return;
            File.WriteAllText(_logFilePath, "");
        }
        catch
        {
            // best-effort; logging continues
        }
    }

    public void Log(LogLevel level, string message)
    {
        if (level < _level) return;
        var line = $"{DateTimeOffset.Now:O} [{level}] {message}";
        Directory.CreateDirectory(Path.GetDirectoryName(_logFilePath)!);
        File.AppendAllText(_logFilePath, line + Environment.NewLine);
    }

    public void Info(string message) => Log(LogLevel.Info, message);
    public void Warn(string message) => Log(LogLevel.Warn, message);
    public void Error(string message) => Log(LogLevel.Error, message);
}

