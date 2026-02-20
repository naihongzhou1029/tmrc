using System.IO;

namespace Tmrc.Cli.Indexing;

/// <summary>
/// Speech-to-text for segment audio. Not implemented on Windows yet; returns null.
/// Future: Windows.Media.SpeechRecognition or similar to populate stt_text for ask/export.
/// </summary>
public static class SegmentStt
{
    public static bool IsAvailable() => false;

    /// <summary>Returns recognized text from segment audio, or null if unavailable / no speech.</summary>
    /// <param name="segmentPath">Path to segment file (e.g. .mp4 with audio).</param>
    public static string? Recognize(string segmentPath)
    {
        if (string.IsNullOrEmpty(segmentPath) || !File.Exists(segmentPath))
            return null;
        return null;
    }
}
