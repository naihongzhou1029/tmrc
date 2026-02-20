using System;
using System.Collections.Generic;
using System.IO;
using System.Threading.Tasks;
using Tmrc.Core.Config;
using Tmrc.Core.Storage;
using Xunit;

namespace Tmrc.Tests;

public class StorageTests
{
    [Fact(DisplayName = "Storage root default from config")]
    public void StorageRootDefaultFromConfig()
    {
        var cfg = ConfigLoader.LoadFromYaml("");
        var expected = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            ".tmrc");
        Assert.Equal(Path.GetFullPath(expected), Path.GetFullPath(cfg.StorageRoot));
    }

    [Fact(DisplayName = "Storage root override")]
    public void StorageRootOverride()
    {
        var cfg = ConfigLoader.LoadFromYaml("storage_root: C:/tmp/tmrc-test");
        Assert.Equal("C:/tmp/tmrc-test", cfg.StorageRoot);
    }

    [Fact(DisplayName = "Directory layout after install")]
    public void DirectoryLayoutAfterInstall()
    {
        var tmp = Path.Combine(Path.GetTempPath(), "tmrc-install-" + Guid.NewGuid());
        try
        {
            var storage = new StorageManager(tmp);
            var configPath = Path.Combine(tmp, "config.yaml");
            storage.EnsureLayout(configPath);

            Assert.True(Directory.Exists(tmp));
            Assert.True(Directory.Exists(Path.Combine(tmp, "index")));
            Assert.True(Directory.Exists(Path.Combine(tmp, "segments")));
            Assert.True(File.Exists(configPath));
            Assert.False(File.Exists(Path.Combine(tmp, "tmrc.pid")));
        }
        finally
        {
            if (Directory.Exists(tmp))
            {
                Directory.Delete(tmp, recursive: true);
            }
        }
    }

    [Fact(DisplayName = "Index path per session")]
    public void IndexPathPerSession()
    {
        var mgr = new StorageManager("C:/tmp/tmrc");
        Assert.Equal(
            Path.Combine("C:/tmp/tmrc", "index", "default.sqlite"),
            mgr.IndexPath("default"));
    }

    [Fact(DisplayName = "Index path for named session")]
    public void IndexPathNamedSession()
    {
        var mgr = new StorageManager("C:/tmp/tmrc");
        Assert.Equal(
            Path.Combine("C:/tmp/tmrc", "index", "work.sqlite"),
            mgr.IndexPath("work"));
    }

    [Fact(DisplayName = "Retention max age evicts old segments")]
    public void RetentionMaxAge()
    {
        var tmp = Path.Combine(Path.GetTempPath(), "tmrc-retention-" + Guid.NewGuid());
        var segDir = Path.Combine(tmp, "segments");
        Directory.CreateDirectory(segDir);
        try
        {
            var oldDate = DateTime.Now.AddDays(-10);
            var path1 = Path.Combine(segDir, "old.mp4");
            File.WriteAllBytes(path1, new byte[100]);
            File.SetLastWriteTime(path1, oldDate);
            var path2 = Path.Combine(segDir, "new.mp4");
            File.WriteAllBytes(path2, new byte[100]);

            var retention = new RetentionManager(maxAgeDays: 7, maxDiskBytes: 1_000_000);
            var (deletedCount, deletedPaths) = retention.EvictIfNeeded(segDir);
            Assert.Equal(1, deletedCount);
            Assert.Single(deletedPaths);
            Assert.Equal(Path.GetFullPath(path1), Path.GetFullPath(deletedPaths[0]));
            Assert.False(File.Exists(path1));
            Assert.True(File.Exists(path2));
        }
        finally
        {
            if (Directory.Exists(tmp))
            {
                Directory.Delete(tmp, recursive: true);
            }
        }
    }

    [Fact(DisplayName = "Retention under limits deletes nothing")]
    public void RetentionUnderLimits()
    {
        var tmp = Path.Combine(Path.GetTempPath(), "tmrc-retention-" + Guid.NewGuid());
        var segDir = Path.Combine(tmp, "segments");
        Directory.CreateDirectory(segDir);
        try
        {
            var path = Path.Combine(segDir, "a.mp4");
            File.WriteAllBytes(path, new byte[100]);

            var retention = new RetentionManager(maxAgeDays: 7, maxDiskBytes: 1_000_000);
            var (deletedCount, deletedPaths) = retention.EvictIfNeeded(segDir);
            Assert.Equal(0, deletedCount);
            Assert.Empty(deletedPaths);
            Assert.True(File.Exists(path));
        }
        finally
        {
            if (Directory.Exists(tmp))
            {
                Directory.Delete(tmp, recursive: true);
            }
        }
    }

    [Fact(DisplayName = "Usage report - disk usage")]
    public async Task UsageReport()
    {
        var tmp = Path.Combine(Path.GetTempPath(), "tmrc-usage-" + Guid.NewGuid());
        Directory.CreateDirectory(tmp);
        try
        {
            var mgr = new StorageManager(tmp);
            var usage = await mgr.DiskUsageAsync();
            Assert.True(usage >= 0);
        }
        finally
        {
            if (Directory.Exists(tmp))
            {
                Directory.Delete(tmp, recursive: true);
            }
        }
    }

    [Fact(DisplayName = "TryProbeWritable returns true for writable directory")]
    public void TryProbeWritable_WritableDir_ReturnsTrue()
    {
        var tmp = Path.Combine(Path.GetTempPath(), "tmrc-probe-" + Guid.NewGuid());
        try
        {
            var mgr = new StorageManager(tmp);
            var ok = mgr.TryProbeWritable(out var err);
            Assert.True(ok);
            Assert.Null(err);
        }
        finally
        {
            if (Directory.Exists(tmp))
            {
                Directory.Delete(tmp, recursive: true);
            }
        }
    }

    [Fact(DisplayName = "Crash recovery removes orphan segment files not in index")]
    public void CrashRecovery_RemovesOrphanFiles()
    {
        var tmp = Path.Combine(Path.GetTempPath(), "tmrc-crash-" + Guid.NewGuid());
        var segDir = Path.Combine(tmp, "segments");
        Directory.CreateDirectory(segDir);
        try
        {
            var keptPath = Path.Combine(segDir, "kept.mp4");
            var orphanPath = Path.Combine(segDir, "orphan.mp4");
            File.WriteAllBytes(keptPath, new byte[1]);
            File.WriteAllBytes(orphanPath, new byte[1]);

            var indexedPaths = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
            {
                Path.GetFullPath(keptPath)
            };

            var removed = CrashRecovery.CleanOrphanSegmentFiles(segDir, indexedPaths);

            Assert.Equal(1, removed);
            Assert.True(File.Exists(keptPath));
            Assert.False(File.Exists(orphanPath));
        }
        finally
        {
            if (Directory.Exists(tmp))
            {
                Directory.Delete(tmp, recursive: true);
            }
        }
    }
}

