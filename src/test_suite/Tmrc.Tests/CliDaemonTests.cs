using System;
using System.Diagnostics;
using System.IO;
using System.Threading.Tasks;
using Xunit;

namespace Tmrc.Tests;

public class CliDaemonTests
{
    private static string GetCliDllPath()
    {
        // Resolve the CLI DLL path based on the test assembly location.
        var asmPath = typeof(CliDaemonTests).Assembly.Location;
        var testBinDir = Path.GetDirectoryName(asmPath)
                         ?? throw new InvalidOperationException("Unable to determine test bin directory.");

        // Walk up until we find the solution root (containing Tmrc.sln).
        var dir = testBinDir;
        while (!string.IsNullOrEmpty(dir) &&
               !File.Exists(Path.Combine(dir, "Tmrc.sln")))
        {
            dir = Path.GetDirectoryName(dir);
        }

        if (string.IsNullOrEmpty(dir))
        {
            throw new InvalidOperationException("Unable to locate solution root (Tmrc.sln).");
        }

        var solutionRoot = dir;
        var cliDir = Path.Combine(solutionRoot, "Tmrc.Cli", "bin", "Debug", "net8.0");
        var cliDll = Path.Combine(cliDir, "Tmrc.Cli.dll");

        if (!File.Exists(cliDll))
        {
            throw new FileNotFoundException("Tmrc.Cli assembly not found", cliDll);
        }

        return cliDll;
    }

    private static Process StartCli(string arguments, string workingDirectory)
    {
        var psi = new ProcessStartInfo
        {
            FileName = "dotnet",
            Arguments = $"\"{GetCliDllPath()}\" {arguments}",
            WorkingDirectory = workingDirectory,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true
        };

        return Process.Start(psi)
               ?? throw new InvalidOperationException("Failed to start tmrc CLI process.");
    }

    private static async Task<(int ExitCode, string StdOut, string StdErr)> RunCliAsync(
        string arguments,
        string workingDirectory,
        int timeoutMs = 15000)
    {
        using var proc = StartCli(arguments, workingDirectory);
        var stdoutTask = proc.StandardOutput.ReadToEndAsync();
        var stderrTask = proc.StandardError.ReadToEndAsync();

        if (!proc.WaitForExit(timeoutMs))
        {
            try
            {
                proc.Kill(true);
            }
            catch
            {
                // ignore cleanup failures in timeout path
            }
        }

        await Task.WhenAll(stdoutTask, stderrTask);
        return (proc.ExitCode, stdoutTask.Result, stderrTask.Result);
    }
    private static void KillProcessSafe(Process? process)
    {
        if (process is null)
        {
            return;
        }

        try
        {
            if (process.HasExited)
            {
                return;
            }

            process.Kill(true);
            process.WaitForExit(5000);
        }
        catch
        {
            // best-effort cleanup for integration tests
        }
    }


    private static string CreateTempConfigRoot()
    {
        var root = Path.Combine(Path.GetTempPath(), "tmrc-cli-" + Guid.NewGuid());
        Directory.CreateDirectory(root);

        var cfg = @"sample_rate_ms = 100
session = default
storage_root = {0}
";
        File.WriteAllText(
            Path.Combine(root, "config.ini"),
            string.Format(cfg, root.Replace("\\", "/")));

        return root;
    }

    private static void WaitForFile(string path, TimeSpan timeout)
    {
        var sw = Stopwatch.StartNew();
        while (sw.Elapsed < timeout)
        {
            if (File.Exists(path))
            {
                return;
            }

            Task.Delay(50).Wait();
        }

        throw new FileNotFoundException("Expected file was not created in time", path);
    }

    [Fact(DisplayName = "Daemon start creates PID and process", Skip = "Daemon E2E test temporarily disabled")]
    public async Task DaemonStartCreatesPidAndProcess()
    {
        var root = CreateTempConfigRoot();
        try
        {
            var (exitCode, _, stderr) = await RunCliAsync("record", root);
            Assert.Equal(0, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stderr));

            var pidPath = Path.Combine(root, "tmrc.pid");
            WaitForFile(pidPath, TimeSpan.FromSeconds(2));

            var text = File.ReadAllText(pidPath).Trim();
            Assert.True(int.TryParse(text, out var pid));

            var proc = Process.GetProcessById(pid);
            Assert.False(proc.HasExited);

            // Cleanup
            KillProcessSafe(proc);
        }
        finally
        {
            if (Directory.Exists(root))
            {
                Directory.Delete(root, recursive: true);
            }
        }
    }

    [Fact(DisplayName = "Daemon already running prevents second start", Skip = "Daemon E2E test temporarily disabled")]
    public async Task DaemonAlreadyRunningPreventsSecondStart()
    {
        var root = CreateTempConfigRoot();
        Process? daemonProc = null;
        try
        {
            var (firstExit, _, _) = await RunCliAsync("record", root);
            Assert.Equal(0, firstExit);

            var pidPath = Path.Combine(root, "tmrc.pid");
            WaitForFile(pidPath, TimeSpan.FromSeconds(2));
            var text = File.ReadAllText(pidPath).Trim();
            Assert.True(int.TryParse(text, out var pid));
            daemonProc = Process.GetProcessById(pid);
            Assert.False(daemonProc.HasExited);

            var (secondExit, _, secondErr) = await RunCliAsync("record --start", root);
            Assert.Equal(1, secondExit);
            Assert.Contains("already in progress", secondErr, StringComparison.OrdinalIgnoreCase);
        }
        finally
        {
            try
            {
                KillProcessSafe(daemonProc);
            }
            catch
            {
                // ignore
            }

            if (Directory.Exists(root))
            {
                Directory.Delete(root, recursive: true);
            }
        }
    }

    [Fact(DisplayName = "Status reports recording when daemon running", Skip = "Daemon E2E test temporarily disabled")]
    public async Task StatusReportsRecording()
    {
        var root = CreateTempConfigRoot();
        Process? daemonProc = null;
        try
        {
            var (startExit, _, _) = await RunCliAsync("record", root);
            Assert.Equal(0, startExit);

            var pidPath = Path.Combine(root, "tmrc.pid");
            WaitForFile(pidPath, TimeSpan.FromSeconds(2));
            var text = File.ReadAllText(pidPath).Trim();
            Assert.True(int.TryParse(text, out var pid));
            daemonProc = Process.GetProcessById(pid);
            Assert.False(daemonProc.HasExited);

            var (statusExit, stdout, _) = await RunCliAsync("status", root);
            Assert.Equal(0, statusExit);
            Assert.Contains("Recording: yes", stdout, StringComparison.OrdinalIgnoreCase);
        }
        finally
        {
            try
            {
                KillProcessSafe(daemonProc);
            }
            catch
            {
                // ignore
            }

            if (Directory.Exists(root))
            {
                Directory.Delete(root, recursive: true);
            }
        }
    }

    [Fact(DisplayName = "record --stop stops daemon and removes PID file", Skip = "Daemon E2E test temporarily disabled")]
    public async Task RecordStopStopsDaemon()
    {
        var root = CreateTempConfigRoot();
        try
        {
            var (startExit, _, _) = await RunCliAsync("record", root);
            Assert.Equal(0, startExit);

            var pidPath = Path.Combine(root, "tmrc.pid");
            WaitForFile(pidPath, TimeSpan.FromSeconds(2));
            var text = File.ReadAllText(pidPath).Trim();
            Assert.True(int.TryParse(text, out var pid));

            var (stopExit, _, _) = await RunCliAsync("record --stop", root);
            Assert.Equal(0, stopExit);

            // Daemon should be gone and PID file removed
            Assert.False(File.Exists(pidPath));
            Assert.ThrowsAny<Exception>(() => Process.GetProcessById(pid));
        }
        finally
        {
            if (Directory.Exists(root))
            {
                Directory.Delete(root, recursive: true);
            }
        }
    }
}

