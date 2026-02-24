using System.Diagnostics;
using System.IO;
using System.Text;

namespace Tmrc.Cli.Recording;

/// <summary>
/// Writes a sequence of BGRA frames to an MP4 file using FFmpeg.
/// Frames are written as BMP to a temp directory, then ffmpeg encodes to H.264.
/// </summary>
public static class Mp4SegmentWriter
{
    private const string FfmpegExe = "ffmpeg";

    public static bool IsAvailable()
    {
        try
        {
            using var process = Process.Start(new ProcessStartInfo
            {
                FileName = FfmpegExe,
                ArgumentList = { "-version" },
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            });
            process?.WaitForExit(2000);
            return process?.ExitCode == 0;
        }
        catch
        {
            return false;
        }
    }

    /// <summary>
    /// Encodes frames to MP4 at the given path. Returns true if successful.
    /// </summary>
    /// <param name="frames">BGRA pixel data per frame (width * height * 4).</param>
    /// <param name="width">Frame width.</param>
    /// <param name="height">Frame height.</param>
    /// <param name="outputPath">Output .mp4 path.</param>
    /// <param name="fps">Frames per second for the output (e.g. 10).</param>
    public static bool Write(
        IReadOnlyList<byte[]> frames,
        int width,
        int height,
        string outputPath,
        double fps = 10.0)
    {
        if (frames.Count == 0)
        {
            return false;
        }

        string? tempDir = null;
        try
        {
            tempDir = Path.Combine(Path.GetTempPath(), "tmrc_" + Guid.NewGuid().ToString("N")[..8]);
            Directory.CreateDirectory(tempDir);

            for (int i = 0; i < frames.Count; i++)
            {
                var path = Path.Combine(tempDir, $"frame_{i:D4}.bmp");
                WriteBmp(path, frames[i], width, height);
            }

            var pattern = Path.Combine(tempDir, "frame_%04d.bmp");
            var startInfo = new ProcessStartInfo
            {
                FileName = FfmpegExe,
                ArgumentList =
                {
                    "-y",
                    "-framerate", fps.ToString("F1", System.Globalization.CultureInfo.InvariantCulture),
                    "-i", pattern,
                    "-c:v", "libx264",
                    "-pix_fmt", "yuv420p",
                    outputPath
                },
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardError = true,
                RedirectStandardOutput = true
            };

            using var process = Process.Start(startInfo);
            if (process is null)
            {
                return false;
            }

            var stdOut = new StringBuilder();
            var stdErr = new StringBuilder();
            process.OutputDataReceived += (_, e) =>
            {
                if (e.Data is not null)
                {
                    stdOut.AppendLine(e.Data);
                }
            };
            process.ErrorDataReceived += (_, e) =>
            {
                if (e.Data is not null)
                {
                    stdErr.AppendLine(e.Data);
                }
            };

            process.BeginOutputReadLine();
            process.BeginErrorReadLine();

            if (!process.WaitForExit(60_000))
            {
                try
                {
                    process.Kill(entireProcessTree: true);
                }
                catch
                {
                    // best-effort
                }

                return false;
            }

            // Ensure async handlers are drained.
            process.WaitForExit();
            return process.ExitCode == 0;
        }
        finally
        {
            if (tempDir != null && Directory.Exists(tempDir))
            {
                try
                {
                    foreach (var file in Directory.EnumerateFiles(tempDir))
                    {
                        File.Delete(file);
                    }
                    Directory.Delete(tempDir);
                }
                catch
                {
                    // best-effort cleanup
                }
            }
        }
    }

    /// <summary>
    /// Writes a single BMP file (24bpp BGR, bottom-up) from BGRA top-down buffer.
    /// </summary>
    private static void WriteBmp(string path, byte[] bgra, int width, int height)
    {
        int rowBytes = ((width * 3 + 3) / 4) * 4;
        int imageSize = rowBytes * height;
        const int fileHeaderSize = 14;
        const int infoHeaderSize = 40;
        int fileSize = fileHeaderSize + infoHeaderSize + imageSize;

        using var fs = new FileStream(path, FileMode.Create, FileAccess.Write, FileShare.None);

        // BITMAPFILEHEADER
        WriteShort(fs, 0x4D42);
        WriteInt(fs, fileSize);
        WriteShort(fs, 0);
        WriteShort(fs, 0);
        WriteInt(fs, fileHeaderSize + infoHeaderSize);

        // BITMAPINFOHEADER
        WriteInt(fs, infoHeaderSize);
        WriteInt(fs, width);
        WriteInt(fs, height);
        WriteShort(fs, 1);
        WriteShort(fs, 24);
        WriteInt(fs, 0);
        WriteInt(fs, imageSize);
        WriteInt(fs, 0);
        WriteInt(fs, 0);
        WriteInt(fs, 0);
        WriteInt(fs, 0);

        // Pixels: bottom-up BGR (flip from top-down BGRA)
        var row = new byte[rowBytes];
        for (int y = height - 1; y >= 0; y--)
        {
            int srcOffset = y * width * 4;
            int dstOffset = 0;
            for (int x = 0; x < width; x++)
            {
                row[dstOffset++] = bgra[srcOffset + 2];
                row[dstOffset++] = bgra[srcOffset + 1];
                row[dstOffset++] = bgra[srcOffset];
                srcOffset += 4;
            }
            fs.Write(row, 0, rowBytes);
        }
    }

    private static void WriteShort(Stream s, int value)
    {
        s.WriteByte((byte)(value & 0xFF));
        s.WriteByte((byte)((value >> 8) & 0xFF));
    }

    private static void WriteInt(Stream s, int value)
    {
        s.WriteByte((byte)(value & 0xFF));
        s.WriteByte((byte)((value >> 8) & 0xFF));
        s.WriteByte((byte)((value >> 16) & 0xFF));
        s.WriteByte((byte)((value >> 24) & 0xFF));
    }
}
