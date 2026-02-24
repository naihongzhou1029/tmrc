using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.IO.Pipes;
using System.Threading;
using System.Threading.Tasks;
using Tmrc.Core.Config;
using Tmrc.Core.Indexing;
using Tmrc.Core.Recall;
using Tmrc.Core.Storage;
using Tmrc.Core.Support;
using Tmrc.Core.Recording;
using Tmrc.Cli.Capture;
using Tmrc.Cli.Export;
using Tmrc.Cli.Indexing;
using Tmrc.Cli.Native;
using Tmrc.Cli.Recording;
using Tmrc.Cli.Support;

namespace Tmrc.Cli;

public static class Program
{
    public static int Main(string[] args)
    {
        if (args.Length == 0)
        {
            PrintUsage();
            return 1;
        }

        if (string.Equals(args[0], "--debug", StringComparison.OrdinalIgnoreCase))
        {
            Environment.SetEnvironmentVariable("TMRC_DEBUG", "1", EnvironmentVariableTarget.Process);
            args = args.Length == 1 ? Array.Empty<string>() : args[1..];
        }

        if (args.Length == 0)
        {
            PrintUsage();
            return 1;
        }

        var cmd = args[0];
        var tail = args[1..];

        switch (cmd)
        {
            case "record":
                return Record(tail);
            case "status":
                return Status(tail);
            case "export":
                return Export(tail);
            case "ask":
                return Ask(tail);
            case "install":
                return Install(tail);
            case "uninstall":
                return Uninstall(tail);
            case "wipe":
                return Wipe(tail);
            case "reindex":
                return Reindex(tail);
            case "--version":
                Console.WriteLine(TmrcVersion.Current);
                return 0;
            case "__daemon":
                return RunDaemon();
            default:
                Console.Error.WriteLine($"Unknown command: {cmd}");
                PrintUsage();
                return 1;
        }
    }

    private static void PrintUsage()
    {
        Console.WriteLine("tmrc (Windows) - Time Machine Recall Commander");
        Console.WriteLine("Usage: tmrc [--debug] <command> [options]");
        Console.WriteLine("Commands: record, status, export, ask, install, uninstall, wipe, reindex, --version");
        Console.WriteLine("  --debug    Enable verbose logging (same as TMRC_DEBUG=1). Daemon inherits when started with tmrc --debug record.");
    }

    private static TmrcConfig LoadConfig()
    {
        var root = Directory.GetCurrentDirectory();
        var configPath = Path.Combine(root, "config.yaml");
        return ConfigLoader.LoadFromFile(configPath);
    }

    private static StorageManager CreateStorageManager()
    {
        var cfg = LoadConfig();
        return new StorageManager(cfg.StorageRoot);
    }

    private static bool TryGetRunningDaemon(
        StorageManager storage,
        out int pid,
        out Process? process)
    {
        pid = 0;
        process = null;

        if (!File.Exists(storage.PidFilePath))
        {
            return false;
        }

        var text = File.ReadAllText(storage.PidFilePath).Trim();
        if (!int.TryParse(text, out pid))
        {
            return false;
        }

        try
        {
            var proc = Process.GetProcessById(pid);
            if (proc.HasExited)
            {
                return false;
            }

            process = proc;
            return true;
        }
        catch
        {
            return false;
        }
    }

    private static int Record(string[] args)
    {
        // record           -> toggle
        // record --start   -> start
        // record --stop    -> stop
        // record --status  -> status
        if (args.Length == 0)
        {
            return ToggleRecording();
        }

        var sub = args[0];
        switch (sub)
        {
            case "--start":
                return StartRecording();
            case "--stop":
                return StopRecording();
            case "--status":
                return Status(Array.Empty<string>());
            default:
                Console.Error.WriteLine($"Unknown record option: {sub}");
                Console.Error.WriteLine("Usage: tmrc record [--start|--stop|--status]");
                return 1;
        }
    }

    private static int ToggleRecording()
    {
        var storage = CreateStorageManager();
        return TryGetRunningDaemon(storage, out _, out _)
            ? StopRecording()
            : StartRecording();
    }

    private static int StartRecording()
    {
        var storage = CreateStorageManager();

        if (TryGetRunningDaemon(storage, out var existingPid, out _))
        {
            Console.Error.WriteLine(
                $"Recording is already in progress (PID {existingPid}).");
            return 1;
        }

        Directory.CreateDirectory(Path.GetDirectoryName(storage.PidFilePath)!);

        var assemblyPath = typeof(Program).Assembly.Location;
        ProcessStartInfo psi;
        if (string.Equals(Path.GetExtension(assemblyPath), ".dll", StringComparison.OrdinalIgnoreCase))
        {
            // Framework-dependent deployment: use dotnet host to run the DLL.
            // Environment.ProcessPath may point to testhost/vstest in tests and break daemon launch.
            var host = "dotnet";
            psi = new ProcessStartInfo
            {
                FileName = host,
                Arguments = $"\"{assemblyPath}\" __daemon",
                UseShellExecute = false,
                RedirectStandardInput = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true,
                WorkingDirectory = Directory.GetCurrentDirectory()
            };
        }
        else
        {
            // Self-contained exe case.
            psi = new ProcessStartInfo
            {
                FileName = assemblyPath,
                Arguments = "__daemon",
                UseShellExecute = false,
                RedirectStandardInput = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true,
                WorkingDirectory = Directory.GetCurrentDirectory()
            };
        }

        var proc = Process.Start(psi);
        if (proc is null)
        {
            Console.Error.WriteLine("Failed to start recorder daemon.");
            return 1;
        }

        // Give daemon a brief moment to write PID file.
        Task.Delay(250).Wait();

        Console.WriteLine("Recording started.");
        return 0;
    }

    private static int StopRecording()
    {
        var storage = CreateStorageManager();
        if (!TryGetRunningDaemon(storage, out var pid, out var proc))
        {
            Console.Error.WriteLine("Recording is not currently running.");
            // Treat as non-fatal; exit code 1 signals "nothing to stop".
            return 1;
        }

        try
        {
            // Prefer a graceful shutdown via IPC; fall back to Kill if it fails.
            TrySendDaemonShutdown();

            if (!proc!.WaitForExit(5000))
            {
                // Fallback: force kill if the daemon did not exit in time.
                proc.Kill(true);
                if (!proc.WaitForExit(5000))
                {
                    Console.Error.WriteLine("Recorder daemon did not exit in time.");
                    return 1;
                }
            }
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"Failed to stop recorder daemon (PID {pid}): {ex.Message}");
            return 1;
        }

        try
        {
            if (File.Exists(storage.PidFilePath))
            {
                File.Delete(storage.PidFilePath);
            }
        }
        catch
        {
            // best-effort
        }

        Console.WriteLine("Recording stopped.");
        return 0;
    }

    private static int Status(string[] args)
    {
        var cfg = LoadConfig();
        var storage = new StorageManager(cfg.StorageRoot);
        var segmentCount = 0;
        try
        {
            var indexPath = storage.IndexPath(cfg.Session);
            if (File.Exists(indexPath))
            {
                var indexStore = new IndexStore(indexPath);
                segmentCount = indexStore.ListAllSegments().Count;
            }
        }
        catch
        {
            // ignore index errors; status should still be available
        }

        var isRecording = TryGetRunningDaemon(storage, out var pid, out var process);
        Console.WriteLine($"Recording: {(isRecording ? "yes" : "no")}");
        if (isRecording)
        {
            Console.WriteLine($"Recorder PID: {pid}");
        }
        Console.WriteLine($"Storage root: {storage.StorageRoot}");
        Console.WriteLine($"Configured sample rate (ms): {cfg.SampleRateMs}");
        Console.WriteLine($"Configured max segment duration (ms): {cfg.SegmentMaxDurationMs}");
        Console.WriteLine($"Configured capture diff threshold: {cfg.CaptureDiffThreshold}");
        Console.WriteLine($"Recorded segments: {segmentCount}");
        Console.WriteLine($"Recording uptime: {(isRecording && process is not null ? TryGetRecordingUptime(process) : "n/a")}");

        try
        {
            var usage = storage.DiskUsageAsync().GetAwaiter().GetResult();
            Console.WriteLine($"Disk usage: {FormatDiskUsage(usage)}");
        }
        catch
        {
            // ignore disk usage errors; status still useful
        }

        return 0;
    }

    private static string FormatElapsed(TimeSpan elapsed)
    {
        if (elapsed < TimeSpan.Zero)
        {
            elapsed = TimeSpan.Zero;
        }

        if (elapsed.TotalHours >= 1)
        {
            return $"{(int)elapsed.TotalHours}h {elapsed.Minutes:D2}m {elapsed.Seconds:D2}s";
        }

        if (elapsed.TotalMinutes >= 1)
        {
            return $"{elapsed.Minutes}m {elapsed.Seconds:D2}s";
        }

        return $"{elapsed.Seconds}s";
    }

    private static string TryGetRecordingUptime(Process process)
    {
        try
        {
            return FormatElapsed(DateTimeOffset.UtcNow - process.StartTime.ToUniversalTime());
        }
        catch
        {
            return "unknown";
        }
    }

    private static string FormatDiskUsage(long bytes)
    {
        if (bytes < 0)
        {
            bytes = 0;
        }

        const double mb = 1024d * 1024d;
        const double gb = 1024d * 1024d * 1024d;

        if (bytes < 1024)
        {
            return $"{bytes} bytes";
        }

        if (bytes < (long)gb)
        {
            var usageMb = bytes / mb;
            return $"{usageMb:F1} MB";
        }

        var usageGb = bytes / gb;
        return $"{usageGb:F1} GB";
    }

    private static int Export(string[] args)
    {
        string? fromExpr = null;
        string? toExpr = null;
        string? query = null;
        string? sinceExpr = null;
        string? untilExpr = null;
        string? outputPath = null;
        string format = "mp4";

        for (var i = 0; i < args.Length; i++)
        {
            var a = args[i];
            if (a == "--from" && i + 1 < args.Length)
            {
                fromExpr = args[++i];
            }
            else if (a == "--to" && i + 1 < args.Length)
            {
                toExpr = args[++i];
            }
            else if (a == "--query" && i + 1 < args.Length)
            {
                query = args[++i];
            }
            else if (a == "--since" && i + 1 < args.Length)
            {
                sinceExpr = args[++i];
            }
            else if (a == "--until" && i + 1 < args.Length)
            {
                untilExpr = args[++i];
            }
            else if ((a == "-o" || a == "--output") && i + 1 < args.Length)
            {
                outputPath = args[++i];
            }
            else if ((a == "--format" || a == "-f") && i + 1 < args.Length)
            {
                format = args[++i].ToLowerInvariant();
            }
        }

        if (format != "mp4" && format != "gif" && format != "manifest")
        {
            Console.Error.WriteLine("--format must be mp4, gif, or manifest.");
            return 1;
        }

        var useQuery = !string.IsNullOrWhiteSpace(query);
        if (useQuery && (!string.IsNullOrWhiteSpace(fromExpr) || !string.IsNullOrWhiteSpace(toExpr)))
        {
            Console.Error.WriteLine("Do not use --from/--to together with --query. Use either time range or query.");
            return 1;
        }

        if (!useQuery && (string.IsNullOrWhiteSpace(fromExpr) || string.IsNullOrWhiteSpace(toExpr)))
        {
            Console.Error.WriteLine("Provide either --from and --to, or --query.");
            return 1;
        }

        var cfg = LoadConfig();
        var storage = new StorageManager(cfg.StorageRoot);
        var indexPath = storage.IndexPath(cfg.Session);

        if (!File.Exists(indexPath))
        {
            Console.Error.WriteLine("No index found; nothing to export.");
            return 1;
        }

        var now = DateTimeOffset.Now;
        var store = new IndexStore(indexPath);
        TimeRange range;

        if (useQuery)
        {
            DateTimeOffset from;
            DateTimeOffset to;
            if (sinceExpr is not null || untilExpr is not null)
            {
                var since = sinceExpr ?? "1d ago";
                var until = untilExpr ?? "now";
                var scope = TimeRangeParser.ParseRelative(since, until, now);
                from = scope.From;
                to = scope.To;
            }
            else
            {
                to = now;
                from = now.AddHours(-24);
            }

            var scopeRows = store.QueryByTimeRange(from, to);
            var q = query!.Trim().ToLowerInvariant();
            var matches = new List<IndexStore.SegmentRow>();
            foreach (var row in scopeRows)
            {
                var text = (row.OcrText ?? string.Empty) + " " + (row.SttText ?? string.Empty);
                if (text.ToLowerInvariant().Contains(q))
                    matches.Add(row);
            }

            if (matches.Count == 0)
            {
                Console.Error.WriteLine("No segments matched the query in the given time scope.");
                return 1;
            }

            var mergedFrom = matches[0].Start;
            var mergedTo = matches[0].End;
            foreach (var r in matches)
            {
                if (r.Start < mergedFrom) mergedFrom = r.Start;
                if (r.End > mergedTo) mergedTo = r.End;
            }
            range = new TimeRange(mergedFrom, mergedTo);
        }
        else
        {
            try
            {
                range = TimeRangeParser.ParseRelative(fromExpr!, toExpr!, now);
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine($"Failed to parse time range: {ex.Message}");
                return 1;
            }
        }

        if (string.IsNullOrWhiteSpace(outputPath))
        {
            outputPath = ExportPathHelper.GetDefaultExportPath(cfg.Session, range, format);
        }

        var rows = store.QueryByTimeRange(range.From, range.To);
        if (rows.Count == 0)
        {
            Console.Error.WriteLine("No segments found in the requested time range.");
            return 1;
        }

        var ordered = new List<IndexStore.SegmentRow>();
        foreach (var row in rows)
        {
            if (string.IsNullOrWhiteSpace(row.Path) || !File.Exists(row.Path))
            {
                Console.Error.WriteLine($"Missing segment file for id {row.Id}; aborting export.");
                return 1;
            }

            ordered.Add(row);
        }

        ordered.Sort((a, b) => a.Start.CompareTo(b.Start));

        if (format == "mp4" || format == "gif")
        {
            foreach (var row in ordered)
            {
                if (!string.Equals(Path.GetExtension(row.Path), ".mp4", StringComparison.OrdinalIgnoreCase))
                {
                    Console.Error.WriteLine($"Segment {row.Id} is not MP4 ({row.Path}). Only MP4 segments can be stitched. Record with FFmpeg on PATH to get MP4 segments.");
                    return 1;
                }
            }

            var paths = ordered.ConvertAll(r => r.Path!);

            if (!VideoExport.IsAvailable())
            {
                Console.Error.WriteLine("FFmpeg is required for video export. Install FFmpeg and ensure it is on PATH.");
                return 1;
            }

            var outDir = Path.GetDirectoryName(outputPath);
            if (!string.IsNullOrEmpty(outDir))
            {
                Directory.CreateDirectory(outDir);
            }

            var ok = format == "gif"
                ? VideoExport.StitchToGif(paths, outputPath, cfg.ExportQuality)
                : VideoExport.StitchToMp4(paths, outputPath, cfg.ExportQuality);

            if (!ok)
            {
                Console.Error.WriteLine("Export failed (FFmpeg error). Check that segment files are valid MP4.");
                return 1;
            }

            Console.WriteLine($"Exported {ordered.Count} segment(s) to {outputPath} ({format}).");
            return 0;
        }

        // manifest
        try
        {
            var outDir = Path.GetDirectoryName(outputPath);
            if (!string.IsNullOrEmpty(outDir))
            {
                Directory.CreateDirectory(outDir);
            }

            using var writer = new StreamWriter(outputPath, append: false);
            writer.WriteLine("# tmrc export manifest");
            writer.WriteLine($"# from: {range.From:O}");
            writer.WriteLine($"# to:   {range.To:O}");
            writer.WriteLine();

            foreach (var row in ordered)
            {
                writer.WriteLine($"{row.Start:O} -> {row.End:O} :: {row.Path}");
            }
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"Failed to write export file: {ex.Message}");
            return 1;
        }

        Console.WriteLine($"Exported {ordered.Count} segment reference(s) to {outputPath} (manifest).");
        return 0;
    }

    private static int Ask(string[] args)
    {
        if (args.Length == 0)
        {
            Console.Error.WriteLine("Usage: tmrc ask \"query\" [--since <expr>] [--until <expr>]");
            return 1;
        }

        string? sinceExpr = null;
        string? untilExpr = null;
        var queryParts = new System.Collections.Generic.List<string>();

        for (var i = 0; i < args.Length; i++)
        {
            var a = args[i];
            if (a == "--since" && i + 1 < args.Length)
            {
                sinceExpr = args[++i];
            }
            else if (a == "--until" && i + 1 < args.Length)
            {
                untilExpr = args[++i];
            }
            else
            {
                queryParts.Add(a);
            }
        }

        var query = string.Join(" ", queryParts).Trim();
        if (string.IsNullOrWhiteSpace(query))
        {
            Console.Error.WriteLine("Ask query must not be empty.");
            return 1;
        }

        var cfg = LoadConfig();
        var storage = new StorageManager(cfg.StorageRoot);
        var indexPath = storage.IndexPath(cfg.Session);

        if (!File.Exists(indexPath))
        {
            Console.WriteLine("Index is empty; no recordings available for ask.");
            return 0;
        }

        var now = DateTimeOffset.Now;
        DateTimeOffset from;
        DateTimeOffset to;

        if (sinceExpr is not null || untilExpr is not null)
        {
            var fromExpr = sinceExpr ?? "1d ago";
            var toExpr = untilExpr ?? "now";
            var range = TimeRangeParser.ParseRelative(fromExpr, toExpr, now);
            from = range.From;
            to = range.To;
        }
        else
        {
            // Default: last 24h.
            to = now;
            from = now.AddHours(-24);
        }

        var store = new IndexStore(indexPath);
        var rows = store.QueryByTimeRange(from, to);

        if (rows.Count == 0)
        {
            Console.WriteLine("No matches found in the given time range.");
            return 0;
        }

        var results = new System.Collections.Generic.List<IndexStore.SegmentRow>();
        var q = query.ToLowerInvariant();

        foreach (var row in rows)
        {
            var text = (row.OcrText ?? string.Empty) + " " + (row.SttText ?? string.Empty);
            if (text.ToLowerInvariant().Contains(q))
            {
                results.Add(row);
            }
        }

        if (results.Count == 0)
        {
            Console.WriteLine("No matches found for query in the given time range.");
            return 0;
        }

        var maxToShow = Math.Min(5, results.Count);
        for (var i = 0; i < maxToShow; i++)
        {
            var r = results[i];
            var tsLocal = r.Start.ToLocalTime().ToString("yyyy-MM-dd HH:mm:ss");
            var snippetSource = r.OcrText ?? r.SttText ?? string.Empty;
            var snippet = snippetSource.Length > 80 ? snippetSource[..80] + "..." : snippetSource;
            Console.WriteLine($"{i + 1}. {tsLocal} [{r.Id}] {snippet}");
        }

        if (results.Count > maxToShow)
        {
            Console.WriteLine($"(+{results.Count - maxToShow} more matches)");
        }

        return 0;
    }

    private static int Install(string[] args)
    {
        var cfg = LoadConfig();
        var storage = new StorageManager(cfg.StorageRoot);
        var configPath = Path.Combine(cfg.StorageRoot, "config.yaml");
        storage.EnsureLayout(configPath);
        Console.WriteLine($"Installed tmrc storage at {cfg.StorageRoot}");
        return 0;
    }

    private static int Uninstall(string[] args)
    {
        var removeData = false;
        for (var i = 0; i < args.Length; i++)
        {
            if (args[i] == "--remove-data")
            {
                removeData = true;
                break;
            }
        }

        var cfg = LoadConfig();
        var storage = new StorageManager(cfg.StorageRoot);

        if (TryGetRunningDaemon(storage, out var pid, out var proc))
        {
            Console.WriteLine("Stopping recorder daemon...");
            try
            {
                TrySendDaemonShutdown();
                proc?.WaitForExit(5000);
                if (proc is { HasExited: false })
                {
                    proc.Kill(true);
                    proc.WaitForExit(5000);
                }
            }
            catch { /* best-effort */ }
            try
            {
                if (File.Exists(storage.PidFilePath))
                    File.Delete(storage.PidFilePath);
            }
            catch { }
        }

        if (removeData && Directory.Exists(cfg.StorageRoot))
        {
            try
            {
                Directory.Delete(cfg.StorageRoot, recursive: true);
                Console.WriteLine($"Removed tmrc data at {cfg.StorageRoot}");
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine($"Failed to remove {cfg.StorageRoot}: {ex.Message}");
                return 1;
            }
        }
        else if (Directory.Exists(cfg.StorageRoot))
        {
            Console.WriteLine($"tmrc data present at {cfg.StorageRoot}. Use --remove-data to delete it.");
        }

        return 0;
    }

    private static int Wipe(string[] args)
    {
        var cfg = LoadConfig();
        var storage = new StorageManager(cfg.StorageRoot);
        try
        {
            if (Directory.Exists(storage.SegmentsDirectory))
            {
                Directory.Delete(storage.SegmentsDirectory, recursive: true);
            }
            Directory.CreateDirectory(storage.SegmentsDirectory);

            var indexDir = Path.GetDirectoryName(storage.IndexPath(cfg.Session));
            if (!string.IsNullOrEmpty(indexDir))
            {
                if (Directory.Exists(indexDir))
                {
                    Directory.Delete(indexDir, recursive: true);
                }

                Directory.CreateDirectory(indexDir);
            }
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"Failed to wipe recordings/index: {ex.Message}");
            return 1;
        }

        Console.WriteLine("All recordings and index wiped.");
        return 0;
    }

    private static int Reindex(string[] args)
    {
        var force = false;
        for (var i = 0; i < args.Length; i++)
        {
            if (args[i] == "--force")
            {
                force = true;
                break;
            }
        }

        var cfg = LoadConfig();
        var storage = new StorageManager(cfg.StorageRoot);
        var indexPath = storage.IndexPath(cfg.Session);

        if (!File.Exists(indexPath))
        {
            Console.Error.WriteLine("No index found; run recording first or use tmrc install.");
            return 1;
        }

        if (!SegmentOcr.IsAvailable())
        {
            Console.Error.WriteLine("Tesseract and FFmpeg are required for reindex. Install both and ensure they are on PATH.");
            return 1;
        }

        var store = new IndexStore(indexPath);
        var all = store.ListAllSegments();
        var processed = 0;
        var skipped = 0;
        var failed = 0;

        foreach (var row in all)
        {
            if (string.IsNullOrWhiteSpace(row.Path) || !string.Equals(Path.GetExtension(row.Path), ".mp4", StringComparison.OrdinalIgnoreCase))
            {
                skipped++;
                continue;
            }
            if (!File.Exists(row.Path))
            {
                skipped++;
                continue;
            }
            if (!force && !string.IsNullOrEmpty(row.OcrText))
            {
                skipped++;
                continue;
            }

            var ocrText = SegmentOcr.Recognize(row.Path, cfg.OcrRecognitionLanguages);
            store.UpsertSegment(row.Id, row.Start, row.End, row.Path, ocrText ?? row.OcrText, row.SttText);
            if (ocrText != null)
                processed++;
            else
                failed++;
        }

        Console.WriteLine($"Reindex complete: {processed} segment(s) indexed, {skipped} skipped, {failed} OCR failed.");
        return 0;
    }

    private static void TrySendDaemonShutdown()
    {
        try
        {
            using var client = new NamedPipeClientStream(
                ".",
                "tmrc-daemon",
                PipeDirection.InOut,
                PipeOptions.None);

            client.Connect(1000);

            using var writer = new StreamWriter(client) { AutoFlush = true };
            using var reader = new StreamReader(client);

            writer.WriteLine("shutdown");
            reader.ReadLine(); // best-effort ack
        }
        catch
        {
            // IPC is best-effort; StopRecording will fall back to Kill.
        }
    }

    private static int RunDaemon()
    {
        var cfg = LoadConfig();
        var storage = new StorageManager(cfg.StorageRoot);
        var notifier = new WindowsToastNotifier();

        Directory.CreateDirectory(Path.GetDirectoryName(storage.PidFilePath)!);

        if (!storage.TryProbeWritable(out var writableError))
        {
            notifier.Toast("tmrc", "Storage not writable: " + (writableError ?? "unknown"));
            Console.Error.WriteLine($"Storage not writable: {writableError}");
            return 1;
        }

        var pid = Environment.ProcessId;
        File.WriteAllText(storage.PidFilePath, pid.ToString());

        var logLevel = string.Equals(Environment.GetEnvironmentVariable("TMRC_DEBUG"), "1", StringComparison.Ordinal)
            ? LogLevel.Debug
            : ParseLogLevel(cfg.LogLevel);
        var logger = new Logger(storage.LogFilePath, logLevel);

        Directory.CreateDirectory(storage.SegmentsDirectory);

        var indexPath = storage.IndexPath(cfg.Session);
        var indexStore = new IndexStore(indexPath);

        // Crash recovery (spec 8.4): remove orphan segment files (left by previous crashed run, not in index).
        var indexedPaths = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var row in indexStore.ListAllSegments())
        {
            if (!string.IsNullOrEmpty(row.Path))
                indexedPaths.Add(Path.GetFullPath(row.Path));
        }
        var orphanCount = CrashRecovery.CleanOrphanSegmentFiles(storage.SegmentsDirectory, indexedPaths);
        if (orphanCount > 0)
            logger.Info($"Crash recovery: removed {orphanCount} orphan segment file(s).");

        var segmenter = new EventSegmenter();
        var flushedSegments = new List<EventSegmenter.Segment>();
        var frameIndex = 0;
        var sampleIntervalMs = Math.Max(1, (int)cfg.SampleRateMs);
        var baseTime = DateTimeOffset.Now;
        var lastFrameWidth = 0;
        var lastFrameHeight = 0;
        long nextWriteOrder = indexStore.GetMaxWriteOrder() + 1;

        ScreenCapture? screenCapture = null;
        var useRealCapture = false;
        try
        {
            screenCapture = new ScreenCapture(diffThreshold: cfg.CaptureDiffThreshold);
            useRealCapture = true;
            logger.Info("Using real screen capture (GDI).");
        }
        catch (Exception ex)
        {
            logger.Info($"Real capture unavailable ({ex.Message}); using simulated.");
        }

        var useMp4 = Mp4SegmentWriter.IsAvailable();
        if (useMp4)
        {
            logger.Info("Using MP4 segment writer (FFmpeg).");
        }
        else
        {
            logger.Info("FFmpeg not found; writing .bin segments.");
        }

        var useOcr = SegmentOcr.IsAvailable();
        if (useOcr)
        {
            logger.Info("OCR enabled (Tesseract on PATH).");
        }
        else
        {
            logger.Info("Tesseract not found; segments will have no OCR text.");
        }

        var segmentFrames = new List<byte[]>();
        var random = new Random();

        var retention = new RetentionManager(
            maxAgeDays: cfg.RetentionMaxAgeDays,
            maxDiskBytes: cfg.RetentionMaxDiskBytes);

        using var shutdownCts = new CancellationTokenSource();
        var shutdownToken = shutdownCts.Token;

        // IPC server thread: listens for simple text commands over a named pipe.
        var ipcThread = new Thread(() =>
        {
            while (!shutdownToken.IsCancellationRequested)
            {
                try
                {
                    using var server = new NamedPipeServerStream(
                        "tmrc-daemon",
                        PipeDirection.InOut,
                        1,
                        PipeTransmissionMode.Byte,
                        PipeOptions.Asynchronous);

                    server.WaitForConnection();

                    using var reader = new StreamReader(server);
                    using var writer = new StreamWriter(server) { AutoFlush = true };

                    var line = reader.ReadLine();
                    if (string.Equals(line, "shutdown", StringComparison.OrdinalIgnoreCase))
                    {
                        writer.WriteLine("ok");
                        shutdownCts.Cancel();
                    }
                    else
                    {
                        writer.WriteLine("unknown");
                    }
                }
                catch (Exception ex)
                {
                    if (shutdownToken.IsCancellationRequested)
                    {
                        break;
                    }

                    logger.Warn($"IPC server error: {ex.Message}");
                    // Brief pause before attempting to accept a new connection.
                    Thread.Sleep(250);
                }
            }
        })
        {
            IsBackground = true,
            Name = "tmrc-daemon-ipc"
        };

        logger.Info("tmrc daemon starting.");
        ipcThread.Start();

        void EmitFlushedSegments(IList<EventSegmenter.Segment> segmentsToWrite, int frameWidth, int frameHeight)
        {
            foreach (var seg in segmentsToWrite)
            {
                var writeOrder = nextWriteOrder++;
                var start = baseTime.AddMilliseconds(seg.StartFrame * sampleIntervalMs);
                var end = baseTime.AddMilliseconds(seg.EndFrame * sampleIntervalMs);
                var id = Guid.NewGuid().ToString("N");
                var writeMp4 = useMp4 && segmentFrames.Count > 0 && frameWidth > 0 && frameHeight > 0;
                var ext = writeMp4 ? ".mp4" : ".bin";
                var fileName = $"{start.UtcDateTime:yyyyMMdd_HHmmssfff}_{id}{ext}";
                var path = Path.Combine(storage.SegmentsDirectory, fileName);

                try
                {
                    if (writeMp4)
                    {
                        var fps = 1000.0 / sampleIntervalMs;
                        if (Mp4SegmentWriter.Write(segmentFrames, frameWidth, frameHeight, path, fps))
                        {
                            var sttText = SegmentStt.IsAvailable() ? SegmentStt.Recognize(path) : null;
                            indexStore.UpsertSegment(id, start, end, path, ocrText: null, sttText, writeOrder);
                            if (useOcr)
                            {
                                var ocrText = SegmentOcr.Recognize(path, cfg.OcrRecognitionLanguages);
                                if (!string.IsNullOrWhiteSpace(ocrText))
                                {
                                    indexStore.UpsertSegment(id, start, end, path, ocrText, sttText, writeOrder);
                                    logger.Info($"Segment recorded: {id} {start:O} - {end:O} (MP4, OCR)");
                                }
                                else
                                {
                                    logger.Info($"Segment recorded: {id} {start:O} - {end:O} (MP4)");
                                }
                            }
                            else
                            {
                                logger.Info($"Segment recorded: {id} {start:O} - {end:O} (MP4)");
                            }
                        }
                        else
                        {
                            logger.Error($"FFmpeg failed for segment {id}; writing placeholder.");
                            var binPath = Path.Combine(storage.SegmentsDirectory, $"{start.UtcDateTime:yyyyMMdd_HHmmssfff}_{id}.bin");
                            File.WriteAllText(binPath, $"tmrc segment {id}");
                            indexStore.UpsertSegment(id, start, end, binPath, null, SegmentStt.IsAvailable() ? SegmentStt.Recognize(binPath) : null, writeOrder);
                        }
                    }
                    else
                    {
                        File.WriteAllText(path, $"tmrc segment {id} from {start:O} to {end:O}");
                        indexStore.UpsertSegment(id, start, end, path, ocrText: null, sttText: SegmentStt.IsAvailable() ? SegmentStt.Recognize(path) : null, writeOrder);
                        logger.Info($"Segment recorded: {id} {start:O} - {end:O}");
                    }
                }
                catch (Exception ex)
                {
                    logger.Error($"Failed to write segment {id}: {ex.Message}");
                    if (ex is IOException || ex.InnerException is IOException)
                    {
                        notifier.Toast("tmrc", "Disk full or write error; stopping recording.");
                        shutdownCts.Cancel();
                    }
                }
                finally
                {
                    segmentFrames.Clear();
                }
            }
        }

        var maxSegmentDurationMs = cfg.SegmentMaxDurationMs;
        var maxSegmentFrames = Math.Max(1, (int)Math.Ceiling(maxSegmentDurationMs / (double)sampleIntervalMs));
        var pauseWhenLocked = !cfg.RecordWhenLockedOrSleeping;
        var wasPausedForLock = false;

        // Recording loop: real capture (GDI) or simulated; event-based segmenter; MP4 or .bin output.
        while (!shutdownToken.IsCancellationRequested)
        {
            flushedSegments.Clear();
            bool hasEvent;
            byte[]? frameBgra = null;
            int frameWidth = 0, frameHeight = 0;
            var pauseForLockedDesktop = pauseWhenLocked && !WindowsSessionState.IsInteractiveDesktop();

            if (pauseForLockedDesktop)
            {
                hasEvent = false;
                if (!wasPausedForLock)
                {
                    logger.Info("Recording paused while session is locked.");
                }
                wasPausedForLock = true;
            }
            else if (useRealCapture && screenCapture != null)
            {
                if (wasPausedForLock)
                {
                    logger.Info("Session unlocked; recording resumed.");
                    wasPausedForLock = false;
                }

                try
                {
                    var (bgra, evt) = screenCapture.CaptureFrame();
                    hasEvent = evt;
                    if (bgra.Length > 0)
                    {
                        frameBgra = bgra;
                        frameWidth = screenCapture.Width;
                        frameHeight = screenCapture.Height;
                        lastFrameWidth = frameWidth;
                        lastFrameHeight = frameHeight;
                        segmentFrames.Add(bgra);
                    }
                    else
                    {
                        // Keep recording progression even when capture API returns no frame.
                        // Timed forced flush will emit a placeholder segment if needed.
                        logger.Warn("Capture returned empty frame; waiting for timed segment flush.");
                    }
                }
                catch (Exception ex)
                {
                    logger.Warn($"Capture frame failed: {ex.Message}");
                    hasEvent = false;
                }
            }
            else
            {
                if (wasPausedForLock)
                {
                    logger.Info("Session unlocked; recording resumed.");
                    wasPausedForLock = false;
                }
                hasEvent = random.NextDouble() < 0.3;
            }

            segmenter.OnFrame(frameIndex, hasEvent, flushedSegments);

            // Split only active long-running segments; never synthesize activity during idle.
            if (flushedSegments.Count == 0)
            {
                segmenter.FlushIfOpenAndAtLeastFrames(maxSegmentFrames, flushedSegments);
            }

            if (shutdownToken.IsCancellationRequested)
            {
                segmenter.FlushTail(flushedSegments);
            }

            if (logLevel == LogLevel.Debug && (hasEvent || flushedSegments.Count > 0))
                logger.Debug($"frame {frameIndex} hasEvent={hasEvent} flushed={flushedSegments.Count}");

            var emitWidth = frameWidth > 0 ? frameWidth : lastFrameWidth;
            var emitHeight = frameHeight > 0 ? frameHeight : lastFrameHeight;
            EmitFlushedSegments(flushedSegments, emitWidth, emitHeight);

            // Apply retention policy after writing new segments; prune index for evicted paths.
            try
            {
                var (evictedCount, evictedPaths) = retention.EvictIfNeeded(storage.SegmentsDirectory);
                if (evictedCount > 0)
                {
                    indexStore.DeleteByPaths(evictedPaths);
                    logger.Info($"Retention evicted {evictedCount} old segment file(s); index pruned.");
                }
            }
            catch (Exception ex)
            {
                logger.Warn($"Retention check failed: {ex.Message}");
            }

            frameIndex++;
            Thread.Sleep(sampleIntervalMs);
        }

        // If shutdown arrives between loop iterations (e.g. during sleep),
        // flush any in-progress segment so the tail is not dropped.
        flushedSegments.Clear();
        segmenter.FlushTail(flushedSegments);
        EmitFlushedSegments(flushedSegments, lastFrameWidth, lastFrameHeight);

        screenCapture?.Dispose();
        logger.Info("tmrc daemon shutting down.");

        try
        {
            if (File.Exists(storage.PidFilePath))
            {
                File.Delete(storage.PidFilePath);
            }
        }
        catch
        {
            // best-effort
        }

        return 0;
    }

    private static LogLevel ParseLogLevel(string value) =>
        Enum.TryParse<LogLevel>(value, ignoreCase: true, out var level)
            ? level
            : LogLevel.Info;
}

