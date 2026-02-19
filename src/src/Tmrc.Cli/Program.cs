using System;
using System.Diagnostics;
using System.IO;
using System.Threading;
using System.Threading.Tasks;
using Tmrc.Core.Config;
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
        Console.WriteLine("Ask not yet implemented on Windows.");
        return 1;
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

