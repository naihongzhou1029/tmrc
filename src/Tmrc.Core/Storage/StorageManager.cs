using System;
using System.IO;
using System.Linq;
using System.Threading.Tasks;

namespace Tmrc.Core.Storage;

public sealed class StorageManager
{
    public string StorageRoot { get; }

    public StorageManager(string storageRoot)
    {
        StorageRoot = storageRoot;
    }

    public string IndexPath(string session) =>
        Path.Combine(StorageRoot, "index", $"{session}.sqlite");

    public string SegmentsDirectory =>
        Path.Combine(StorageRoot, "segments");

    public string PidFilePath =>
        Path.Combine(StorageRoot, "tmrc.pid");

    public string LogFilePath =>
        Path.Combine(StorageRoot, "tmrc.log");

    public async Task<long> DiskUsageAsync()
    {
        if (!Directory.Exists(StorageRoot))
        {
            return 0;
        }

        return await Task.Run(() =>
        {
            long total = 0;
            var logFullPath = Path.GetFullPath(LogFilePath);
            foreach (var file in Directory.EnumerateFiles(StorageRoot, "*", SearchOption.AllDirectories))
            {
                try
                {
                    if (string.Equals(Path.GetFullPath(file), logFullPath, StringComparison.OrdinalIgnoreCase))
                    {
                        continue;
                    }

                    var info = new FileInfo(file);
                    total += info.Length;
                }
                catch
                {
                    // ignore
                }
            }

            return total;
        });
    }

    public void EnsureLayout(string configPath)
    {
        Directory.CreateDirectory(StorageRoot);
        Directory.CreateDirectory(Path.Combine(StorageRoot, "index"));
        Directory.CreateDirectory(SegmentsDirectory);

        if (!File.Exists(configPath))
        {
            File.WriteAllText(configPath, "# tmrc Windows config\n");
        }
    }

    /// <summary>Returns true if we can write to the storage root (e.g. not read-only or full).</summary>
    public bool TryProbeWritable(out string? errorMessage)
    {
        errorMessage = null;
        try
        {
            Directory.CreateDirectory(StorageRoot);
            var probePath = Path.Combine(StorageRoot, ".tmrc_probe_" + Guid.NewGuid().ToString("N")[..8]);
            File.WriteAllText(probePath, "probe");
            File.Delete(probePath);
            return true;
        }
        catch (Exception ex)
        {
            errorMessage = ex.Message;
            return false;
        }
    }
}

