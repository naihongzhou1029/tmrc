using System;
using System.IO;
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

    private static int Record(string[] args)
    {
        // Placeholder: recording daemon not yet implemented.
        Console.WriteLine("Recording is not yet implemented on Windows.");
        return 0;
    }

    private static int Status(string[] args)
    {
        var cfg = LoadConfig();
        var storage = new StorageManager(cfg.StorageRoot);
        Console.WriteLine("Recording: no");
        Console.WriteLine($"Storage root: {storage.StorageRoot}");
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
}

