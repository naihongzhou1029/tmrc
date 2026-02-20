using System;
using System.Collections.Generic;
using System.IO;

namespace Tmrc.Core.Storage;

/// <summary>Crash recovery per spec 8.4: remove segment files on disk that are not in the index.</summary>
public static class CrashRecovery
{
    /// <summary>Deletes files under segmentsDirectory whose full path is not in indexedFullPaths. Returns count of removed files.</summary>
    public static int CleanOrphanSegmentFiles(string segmentsDirectory, IReadOnlySet<string> indexedFullPaths)
    {
        if (string.IsNullOrEmpty(segmentsDirectory) || !Directory.Exists(segmentsDirectory))
            return 0;
        if (indexedFullPaths is null)
            return 0;

        var removed = 0;
        foreach (var filePath in Directory.EnumerateFiles(segmentsDirectory, "*", SearchOption.AllDirectories))
        {
            var fullPath = Path.GetFullPath(filePath);
            if (indexedFullPaths.Contains(fullPath))
                continue;
            try
            {
                File.Delete(fullPath);
                removed++;
            }
            catch
            {
                // best-effort; caller can log
            }
        }

        return removed;
    }
}
