using System;
using System.IO;
using System.Linq;

namespace Tmrc.Core.Storage;

public sealed class RetentionManager
{
    public int MaxAgeDays { get; }
    public long MaxDiskBytes { get; }

    public RetentionManager(int maxAgeDays, long maxDiskBytes)
    {
        MaxAgeDays = maxAgeDays;
        MaxDiskBytes = maxDiskBytes;
    }

    public int EvictIfNeeded(string segmentsDirectory)
    {
        if (!Directory.Exists(segmentsDirectory))
        {
            return 0;
        }

        var files = Directory.EnumerateFiles(segmentsDirectory, "*", SearchOption.AllDirectories)
            .Select(path => new FileInfo(path))
            .Where(fi => fi.Exists)
            .ToList();

        var now = DateTime.UtcNow;
        int deleted = 0;

        // Evict by age
        if (MaxAgeDays > 0)
        {
            var minDate = now.AddDays(-MaxAgeDays);
            foreach (var fi in files.Where(f => f.LastWriteTimeUtc < minDate).ToList())
            {
                try
                {
                    File.Delete(fi.FullName);
                    deleted++;
                    files.Remove(fi);
                }
                catch
                {
                    // ignore individual delete failures
                }
            }
        }

        // Evict by disk usage
        if (MaxDiskBytes > 0)
        {
            long total = files.Sum(f => f.Length);
            if (total > MaxDiskBytes)
            {
                foreach (var fi in files.OrderBy(f => f.LastWriteTimeUtc).ToList())
                {
                    if (total <= MaxDiskBytes)
                    {
                        break;
                    }

                    try
                    {
                        File.Delete(fi.FullName);
                        deleted++;
                        total -= fi.Length;
                        files.Remove(fi);
                    }
                    catch
                    {
                        // ignore
                    }
                }
            }
        }

        return deleted;
    }
}

