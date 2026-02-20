using System;
using System.Collections.Generic;
using System.IO;
using Microsoft.Data.Sqlite;
using Tmrc.Core.Storage;

namespace Tmrc.Core.Indexing;

public sealed class IndexStore
{
    private readonly string _connectionString;

    public IndexStore(string databasePath)
    {
        if (string.IsNullOrWhiteSpace(databasePath))
        {
            throw new ArgumentException("Database path must be provided", nameof(databasePath));
        }

        Directory.CreateDirectory(Path.GetDirectoryName(databasePath)!);
        _connectionString = new SqliteConnectionStringBuilder
        {
            DataSource = databasePath
        }.ToString();

        EnsureSchema();
    }

    private void EnsureSchema()
    {
        using var conn = new SqliteConnection(_connectionString);
        conn.Open();

        using (var cmd = conn.CreateCommand())
        {
            cmd.CommandText = @"
CREATE TABLE IF NOT EXISTS segments (
    id TEXT PRIMARY KEY,
    start_utc TEXT NOT NULL,
    end_utc TEXT NOT NULL,
    path TEXT,
    ocr_text TEXT,
    stt_text TEXT
);
";
            cmd.ExecuteNonQuery();
        }

        // Backwards-compatible upgrade: ensure the 'path' column exists for
        // databases created before it was introduced.
        using (var pragma = conn.CreateCommand())
        {
            pragma.CommandText = "PRAGMA table_info(segments);";
            using var reader = pragma.ExecuteReader();
            var hasPath = false;
            while (reader.Read())
            {
                var name = reader.GetString(1);
                if (string.Equals(name, "path", StringComparison.OrdinalIgnoreCase))
                {
                    hasPath = true;
                    break;
                }
            }

            if (!hasPath)
            {
                using var alter = conn.CreateCommand();
                alter.CommandText = "ALTER TABLE segments ADD COLUMN path TEXT;";
                alter.ExecuteNonQuery();
            }
        }
    }

    public void UpsertSegment(
        string id,
        DateTimeOffset start,
        DateTimeOffset end,
        string path,
        string? ocrText,
        string? sttText)
    {
        using var conn = new SqliteConnection(_connectionString);
        conn.Open();

        using var cmd = conn.CreateCommand();
        cmd.CommandText = @"
INSERT INTO segments (id, start_utc, end_utc, path, ocr_text, stt_text)
VALUES ($id, $start, $end, $path, $ocr, $stt)
ON CONFLICT(id) DO UPDATE SET
    start_utc = excluded.start_utc,
    end_utc = excluded.end_utc,
    path = excluded.path,
    ocr_text = excluded.ocr_text,
    stt_text = excluded.stt_text;
";
        cmd.Parameters.AddWithValue("$id", id);
        cmd.Parameters.AddWithValue("$start", start.UtcDateTime.ToString("O"));
        cmd.Parameters.AddWithValue("$end", end.UtcDateTime.ToString("O"));
        cmd.Parameters.AddWithValue("$path", path);
        cmd.Parameters.AddWithValue("$ocr", (object?)ocrText ?? DBNull.Value);
        cmd.Parameters.AddWithValue("$stt", (object?)sttText ?? DBNull.Value);
        cmd.ExecuteNonQuery();
    }

    public sealed record SegmentRow(
        string Id,
        DateTimeOffset Start,
        DateTimeOffset End,
        string? Path,
        string? OcrText,
        string? SttText);

    public IReadOnlyList<SegmentRow> QueryByTimeRange(DateTimeOffset from, DateTimeOffset to)
    {
        var results = new List<SegmentRow>();

        using var conn = new SqliteConnection(_connectionString);
        conn.Open();

        using var cmd = conn.CreateCommand();
        cmd.CommandText = @"
SELECT id, start_utc, end_utc, path, ocr_text, stt_text
FROM segments
WHERE start_utc <= $to AND end_utc >= $from
ORDER BY start_utc;
";
        cmd.Parameters.AddWithValue("$from", from.UtcDateTime.ToString("O"));
        cmd.Parameters.AddWithValue("$to", to.UtcDateTime.ToString("O"));

        using var reader = cmd.ExecuteReader();
        while (reader.Read())
        {
            var id = reader.GetString(0);
            var start = DateTimeOffset.Parse(reader.GetString(1), null, System.Globalization.DateTimeStyles.RoundtripKind);
            var end = DateTimeOffset.Parse(reader.GetString(2), null, System.Globalization.DateTimeStyles.RoundtripKind);
            var path = reader.IsDBNull(3) ? null : reader.GetString(3);
            var ocr = reader.IsDBNull(4) ? null : reader.GetString(4);
            var stt = reader.IsDBNull(5) ? null : reader.GetString(5);
            results.Add(new SegmentRow(id, start, end, path, ocr, stt));
        }

        return results;
    }

    /// <summary>
    /// Returns all segments in the index, ordered by start time. Used by reindex to iterate over existing segments.
    /// </summary>
    public IReadOnlyList<SegmentRow> ListAllSegments()
    {
        var results = new List<SegmentRow>();

        using var conn = new SqliteConnection(_connectionString);
        conn.Open();

        using var cmd = conn.CreateCommand();
        cmd.CommandText = @"
SELECT id, start_utc, end_utc, path, ocr_text, stt_text
FROM segments
ORDER BY start_utc;
";

        using var reader = cmd.ExecuteReader();
        while (reader.Read())
        {
            var id = reader.GetString(0);
            var start = DateTimeOffset.Parse(reader.GetString(1), null, System.Globalization.DateTimeStyles.RoundtripKind);
            var end = DateTimeOffset.Parse(reader.GetString(2), null, System.Globalization.DateTimeStyles.RoundtripKind);
            var path = reader.IsDBNull(3) ? null : reader.GetString(3);
            var ocr = reader.IsDBNull(4) ? null : reader.GetString(4);
            var stt = reader.IsDBNull(5) ? null : reader.GetString(5);
            results.Add(new SegmentRow(id, start, end, path, ocr, stt));
        }

        return results;
    }
}

