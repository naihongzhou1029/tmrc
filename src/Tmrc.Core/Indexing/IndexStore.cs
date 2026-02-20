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
    stt_text TEXT,
    write_order INTEGER
);
";
            cmd.ExecuteNonQuery();
        }

        EnsureColumn(conn, "path", "TEXT");
        EnsureColumn(conn, "write_order", "INTEGER");
    }

    private static void EnsureColumn(SqliteConnection conn, string columnName, string columnType)
    {
        using var pragma = conn.CreateCommand();
        pragma.CommandText = "PRAGMA table_info(segments);";
        using var reader = pragma.ExecuteReader();
        var hasColumn = false;
        while (reader.Read())
        {
            var name = reader.GetString(1);
            if (string.Equals(name, columnName, StringComparison.OrdinalIgnoreCase))
            {
                hasColumn = true;
                break;
            }
        }
        reader.Close();

        if (!hasColumn)
        {
            using var alter = conn.CreateCommand();
            alter.CommandText = $"ALTER TABLE segments ADD COLUMN {columnName} {columnType};";
            alter.ExecuteNonQuery();
        }
    }

    /// <summary>Optional monotonic order for stitching (spec 8.5). When null, ordering falls back to start_utc.</summary>
    public void UpsertSegment(
        string id,
        DateTimeOffset start,
        DateTimeOffset end,
        string path,
        string? ocrText,
        string? sttText,
        long? writeOrder = null)
    {
        using var conn = new SqliteConnection(_connectionString);
        conn.Open();

        using var cmd = conn.CreateCommand();
        cmd.CommandText = @"
INSERT INTO segments (id, start_utc, end_utc, path, ocr_text, stt_text, write_order)
VALUES ($id, $start, $end, $path, $ocr, $stt, $write_order)
ON CONFLICT(id) DO UPDATE SET
    start_utc = excluded.start_utc,
    end_utc = excluded.end_utc,
    path = excluded.path,
    ocr_text = excluded.ocr_text,
    stt_text = excluded.stt_text,
    write_order = excluded.write_order;
";
        cmd.Parameters.AddWithValue("$id", id);
        cmd.Parameters.AddWithValue("$start", start.UtcDateTime.ToString("O"));
        cmd.Parameters.AddWithValue("$end", end.UtcDateTime.ToString("O"));
        cmd.Parameters.AddWithValue("$path", path);
        cmd.Parameters.AddWithValue("$ocr", (object?)ocrText ?? DBNull.Value);
        cmd.Parameters.AddWithValue("$stt", (object?)sttText ?? DBNull.Value);
        cmd.Parameters.AddWithValue("$write_order", (object?)writeOrder ?? DBNull.Value);
        cmd.ExecuteNonQuery();
    }

    /// <summary>Max write_order in the index; daemon uses this + 1 for next segment (monotonic ordering).</summary>
    public long GetMaxWriteOrder()
    {
        using var conn = new SqliteConnection(_connectionString);
        conn.Open();
        using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT COALESCE(MAX(write_order), 0) FROM segments;";
        var v = cmd.ExecuteScalar();
        return v is long l ? l : 0L;
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
ORDER BY (write_order IS NULL), write_order ASC, start_utc ASC;
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
ORDER BY (write_order IS NULL), write_order ASC, start_utc ASC;
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

    /// <summary>Removes segment rows whose path is in the given list (e.g. after retention eviction). Paths should match stored path exactly.</summary>
    public void DeleteByPaths(IReadOnlyList<string> paths)
    {
        if (paths is null || paths.Count == 0)
            return;

        using var conn = new SqliteConnection(_connectionString);
        conn.Open();

        foreach (var path in paths)
        {
            using var cmd = conn.CreateCommand();
            cmd.CommandText = "DELETE FROM segments WHERE path = $path;";
            cmd.Parameters.AddWithValue("$path", path);
            cmd.ExecuteNonQuery();
        }
    }
}

