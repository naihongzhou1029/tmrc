using System;
using System.Diagnostics;
using System.IO;
using System.Threading;
using System.Threading.Tasks;
using Tmrc.Core.Config;
using Tmrc.Core.Indexing;
using Tmrc.Core.Recall;
using Tmrc.Core.Storage;
using Tmrc.Core.Support;

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
        Console.WriteLine("Usage: tmrc <command> [options]");
        Console.WriteLine("Commands: record, status, export, ask, install, uninstall, wipe, --version");
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
        // record           -> start
        // record --start   -> start
        // record --stop    -> stop
        var sub = args.Length > 0 ? args[0] : "--start";
        return sub switch
        {
            "--start" => StartRecording(),
            "--stop" => StopRecording(),
            _ => StartRecording()
        };
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
            // Framework-dependent deployment: use current host (dotnet) to run the DLL.
            var host = Environment.ProcessPath ?? "dotnet";
            psi = new ProcessStartInfo
            {
                FileName = host,
                Arguments = $"\"{assemblyPath}\" __daemon",
                UseShellExecute = false,
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
            proc!.Kill(true);
            if (!proc.WaitForExit(5000))
            {
                Console.Error.WriteLine("Recorder daemon did not exit in time.");
                return 1;
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

        var isRecording = TryGetRunningDaemon(storage, out var pid, out _);
        Console.WriteLine($"Recording: {(isRecording ? "yes" : "no")}");
        if (isRecording)
        {
            Console.WriteLine($"Recorder PID: {pid}");
        }
        Console.WriteLine($"Storage root: {storage.StorageRoot}");

        try
        {
            var usage = storage.DiskUsageAsync().GetAwaiter().GetResult();
            Console.WriteLine($"Disk usage (bytes): {usage}");
        }
        catch
        {
            // ignore disk usage errors; status still useful
        }

        return 0;
    }

    private static int Export(string[] args)
    {
        Console.WriteLine("Export not yet implemented on Windows.");
        return 1;
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
        var cfg = LoadConfig();
        if (Directory.Exists(cfg.StorageRoot))
        {
            // Default: keep data; for now just print info.
            Console.WriteLine($"tmrc data present at {cfg.StorageRoot}. Remove manually if desired.");
        }
        return 0;
    }

    private static int Wipe(string[] args)
    {
        var cfg = LoadConfig();
        var storage = new StorageManager(cfg.StorageRoot);
        if (Directory.Exists(storage.SegmentsDirectory))
        {
            Directory.Delete(storage.SegmentsDirectory, recursive: true);
            Directory.CreateDirectory(storage.SegmentsDirectory);
        }
        Console.WriteLine("All recordings wiped (Windows implementation placeholder).");
        return 0;
    }

    private static int RunDaemon()
    {
        var cfg = LoadConfig();
        var storage = new StorageManager(cfg.StorageRoot);

        Directory.CreateDirectory(Path.GetDirectoryName(storage.PidFilePath)!);

        var pid = Environment.ProcessId;
        File.WriteAllText(storage.PidFilePath, pid.ToString());

        // Minimal placeholder daemon loop. Real recording/IPC will be added later phases.
        try
        {
            Thread.Sleep(Timeout.Infinite);
        }
        catch (ThreadInterruptedException)
        {
            // exit
        }

        return 0;
    }
}

