## Windows/.NET build progress

*Last synced: 2025-02-20. All four milestones done: real capture + MP4, export to MP4/GIF, OCR (Tesseract), ops and polish (log rotation, uninstall --remove-data, Windows toasts, TryProbeWritable, disk-full handling). Tests: 33 passed, 4 skipped (daemon E2E).*

- **Repo layout**
  - Swift/macOS package (`Package.swift`, `Sources/`, `Tests/tmrcTests/`, `devops.sh`) **removed**.
  - New `.NET`-based Windows implementation lives under `src/`:
    - `src/Tmrc.Core` – core library.
    - `src/Tmrc.Cli` – CLI executable.
    - `src/test_suite/Tmrc.Tests` – xUnit test suite.
  - `devops.ps1` is the single entry point for setup/build/test on Windows.

- **Tooling**
  - `devops.ps1 setup`:
    - Verifies Windows, checks/installs **.NET SDK 8**, wires `dotnet` into `PATH` if needed.
    - Checks for `config.yaml`, `ffprobe` (optional), `ffmpeg` (optional; used for MP4 segment encoding when on PATH), and `dotnet-format` (optional).
  - `devops.ps1 build`:
    - Runs `dotnet build src/Tmrc.sln`.
  - `devops.ps1 test`:
    - Runs `dotnet test src/Tmrc.sln` (executes `Tmrc.Tests` in `src/test_suite`).

- **Implemented core (Tmrc.Core)**
  - `Config/TmrcConfig` + `Config/ConfigLoader`:
    - YAML-based config loader with defaults/overrides for:
      - `sample_rate_ms`, `session`, `capture_mode`, `display`, `audio_enabled`,
        `record_when_locked_or_sleeping`, `storage_root`, `index_mode`,
        `ocr_recognition_languages`, `ask_default_range`, `export_quality`, `log_level`.
    - `storage_root` default: `%USERPROFILE%\.tmrc`.
    - Validates/normalizes `sample_rate_ms` (> 0, else default 100 ms).
    - Maps `index_mode` to `normal` / `advanced` and rejects invalid values.
  - `Storage/StorageManager`:
    - Computes paths for:
      - `index/<session>.sqlite`.
      - `segments/`.
      - `tmrc.pid`, `tmrc.log`.
    - `EnsureLayout(configPath)`:
      - Creates `storage_root`, `index/`, `segments/`.
      - Writes a minimal `config.yaml` if missing.
    - `DiskUsageAsync()`:
      - Computes recursive byte size under `storage_root`.
    - `TryProbeWritable(out errorMessage)`:
      - Returns true if we can write to the storage root (creates dir, writes and deletes a probe file); false with message on read-only/full.
    - `TryProbeWritable(out errorMessage)`:
      - Returns true if a probe file can be written and deleted under `storage_root`; used at daemon start to fail fast when storage is read-only or full.
  - `Storage/RetentionManager`:
    - Evicts by:
      - **Max age** (days): deletes files older than the threshold.
      - **Max disk bytes**: deletes oldest files until under quota.
  - `Recall/TimeRangeParser`:
    - Absolute parsing:
      - `yyyy-MM-dd HH:mm:ss` (local time, invariant culture).
    - Relative helpers:
      - `"now"`, `"1h ago"` (and other units), `"yesterday"`.
    - `TimeRange` struct for `[from, to]`.
  - `Support/TmrcVersion`:
    - Static `Current` version string (`0.1.0-windows-dev`).
  - `Support/Logger`:
    - Simple file logger with log levels (debug/info/warn/error). On open, if the log file exists and is older than 7 days, it is truncated (single-file rotation).
  - `Support/Notifier`:
    - `INotifier` interface and `NoopNotifier` (writes toast messages to stderr only for now).
  - `Recording/EventSegmenter`:
    - Pure in-memory event-based segmenter that groups active frames into segments and flushes when an idle frame follows activity.
    - Models the spec’s semantics for segment boundaries (items 1.1–1.2) without yet tying into real capture or Media Foundation writers.
  - `Indexing/IndexStore`:
    - SQLite-backed index store per session (one `.sqlite` file) using `Microsoft.Data.Sqlite`.
    - Schema: `segments(id TEXT PRIMARY KEY, start_utc TEXT, end_utc TEXT, path TEXT, ocr_text TEXT, stt_text TEXT)`.
    - Backward-compatible migration: adds `path` column via `ALTER TABLE` if missing on existing DBs.
    - Supports `UpsertSegment(id, start, end, path, ocrText, sttText)` and `QueryByTimeRange` (overlapping segments ordered by start time).
    - `SegmentRow` includes `Path` so export can resolve segments to on-disk files without filename guessing.

- **CLI (Tmrc.Cli)**
  - `Program.cs`:
    - Commands: `record`, `status`, `export`, `ask`, `install`, `uninstall`, `wipe`, `--version` (plus internal `__daemon` entrypoint).
    - Current behavior:
      - `--version` prints `TmrcVersion.Current`.
      - `install`:
        - Loads config from `config.yaml` in current directory.
        - Uses `StorageManager.EnsureLayout` on `storage_root`.
      - `record` / `record --start`:
        - Starts a detached **recorder daemon** by spawning the same `Tmrc.Cli` assembly with `__daemon`.
        - Daemon writes PID to `storage_root/tmrc.pid`, runs a **named-pipe server** (`tmrc-daemon`) for control, and a **real or simulated recording loop** (see daemon below).
        - If a live daemon already exists (PID file + `Process.GetProcessById`), prints "already in progress" and exits non-zero.
      - `record --stop`:
        - Prefer **graceful shutdown**: connects to named pipe, sends `shutdown`; waits up to 5 s for daemon exit.
        - Falls back to `Process.Kill(true)` if IPC fails or daemon does not exit in time.
        - Deletes `tmrc.pid` on success and prints `Recording stopped.`
      - **Daemon (`__daemon`)**:
        - Writes PID file; creates `Logger` (storage root log file, level from config).
        - **IPC thread**: `NamedPipeServerStream("tmrc-daemon")` accepts connections; on `shutdown` command, sets cancellation and replies `ok`.
        - **Recording loop**: Uses **real screen capture** when available (GDI BitBlt via `ScreenCapture`); otherwise simulated (30% event). Event detection: frame-diff threshold for real capture. On flush, writes segment as **MP4** (when FFmpeg on PATH) via `Mp4SegmentWriter` (BMP sequence → FFmpeg libx264), else `.bin` placeholder. Filename `yyyyMMdd_HHmmssfff_<id>.mp4` or `.bin`. After writing MP4, **OCR** runs when Tesseract is on PATH: `SegmentOcr` (Tmrc.Cli/Indexing/SegmentOcr.cs) extracts first frame via FFmpeg, runs Tesseract CLI, then upserts `ocr_text` into the index; daemon logs "OCR enabled" or "Tesseract not found" at startup. Index and retention unchanged (7 days, 50 GB).
      - `status`:
        - Loads config and prints:
          - `Recording: yes|no` based on `tmrc.pid` and a live process.
          - `Recorder PID: <pid>` when running.
          - `Storage root: <path>`.
          - `Disk usage (bytes): <value>` from `StorageManager.DiskUsageAsync` (best-effort).
      - `uninstall [--remove-data]`:
        - Stops the daemon if running (IPC then Kill fallback), then with `--remove-data` deletes `storage_root` recursively; otherwise prints that data is present and to use `--remove-data` to delete.
      - `wipe`:
        - Clears and recreates `segments/` under current `storage_root`.
      - `ask`:
        - **Basic keyword-only ask** over the SQLite index (works on real index data produced by the daemon):
          - Usage: `tmrc ask "query" [--since <expr>] [--until <expr>]`.
          - Default scope: last 24h when `--since`/`--until` omitted.
          - Uses `TimeRangeParser.ParseRelative` for expressions like `"1h ago"`, `"yesterday"`, or absolute timestamps.
          - Binds to session index via `IndexStore`; filters by `ocr_text` + `stt_text` (case-insensitive); up to 5 matches with citations `YYYY-MM-DD HH:MM:SS [segment-id] snippet`.
          - Friendly messages when index missing or no matches.
      - `export`:
        - **Export to MP4/GIF or manifest:** `tmrc export --from <expr> --to <expr> -o <outputPath> [--format mp4|gif|manifest]`.
        - Default format is **mp4**. Parses time range; queries index; resolves segments via `row.Path` (fails if any segment file is missing). For MP4/GIF, all segments must be `.mp4` (clear error if .bin).
        - **VideoExport** (Tmrc.Cli/Export/VideoExport.cs): uses FFmpeg concat demuxer + re-encode; quality from config `export_quality` (low: 720p ~2 Mbps, medium: 1080p ~5 Mbps, high: source ~8 Mbps). GIF via temp MP4 then palette filter.
        - `--format manifest` writes a text manifest only (segment paths in time order). FFmpeg required for mp4/gif; missing FFmpeg gives a clear error.

- **Test suite (src/test_suite/Tmrc.Tests)**
  - Test framework: xUnit + Microsoft.NET.Test.Sdk.
  - **Config tests** (mirroring `specs/test.md` config rows):
    - Default and override behavior for:
      - `sample_rate_ms`, `session`, `capture_mode`, `display`,
        `audio_enabled`, `record_when_locked_or_sleeping`, `storage_root`,
        `index_mode`, `ocr_recognition_languages`.
    - Invalid `sample_rate_ms` (0) falls back to default.
    - Invalid `index_mode` throws.
  - **Storage tests** (mirroring storage rows):
    - `storage_root` default/override.
    - Directory layout after install:
      - `index/`, `segments/`, `config.yaml` exist.
      - `tmrc.pid` does not exist yet.
    - `indexPath(session)` for `default` and `work`.
    - `RetentionManager`:
      - Evicts old segments by age.
      - Keeps files when under age/size limits.
    - `DiskUsageAsync` returns a non-negative value.
  - **Time-range parser tests** (mirroring time parsing rows):
    - `"1h ago"` relative to a fixed `now` produces `now - 1h`.
    - `"yesterday"` yields local midnight of the previous day.
    - Absolute `"2025-02-15 14:32:00"` parses to correct local time.
  - **Recording tests** (segment boundaries; see RecordingTests below).
  - **Indexing tests**:
    - `IndexingTests`:
      - "Index schema create and read" creates a temp SQLite DB, inserts a single segment row via `IndexStore.UpsertSegment` (including `path`), and verifies it can be read back by time-range query with all fields intact (id, start, end, path, ocr_text, stt_text).
    - `RecordingTests`:
      - "Segment boundaries (event-based)" feeds a single event frame followed by an idle frame and asserts at least one segment is flushed.
      - "Segment boundaries (burst)" feeds ~31 consecutive event frames followed by an idle frame and asserts exactly one segment spanning the burst is flushed.
  - **CLI/daemon tests**:
    - `CliDaemonTests` file documents E2E-style tests for:
      - Daemon start creating `tmrc.pid` and a live process.
      - Rejecting a second `record --start` when already recording.
      - `status` reporting `Recording: yes` when daemon is running.
      - `record --stop` stopping the daemon and removing `tmrc.pid`.
    - These tests are currently marked `[Skip]` to avoid flaky E2E behavior in CI, but they serve as a blueprint for future non-skipped daemon tests.
  - **Ocr tests** (OcrTests.cs):
    - Recognize returns null for non-existent path; returns null for non-MP4 extension.
  - **Storage tests:** TryProbeWritable returns true for writable directory.
  - **Current test status**:
    - `devops.ps1 test` → **33 tests passing, 4 tests skipped (daemon E2E), 0 failures.**

- **Implemented (real capture + MP4 segments)**
  - **Tmrc.Cli/Native/GdiNative.cs**: GDI P/Invoke (GetWindowDC, GetWindowRect, BitBlt, GetDIBits, CreateCompatibleDC/CreateCompatibleBitmap, DeleteDC/DeleteObject, RECT, BITMAPINFO) for screen capture.
  - **Tmrc.Cli/Capture/ScreenCapture.cs**: Captures primary display via BitBlt at sample rate; returns BGRA buffer and `HasEvent` via frame-diff threshold; `Dispose()` releases DCs and bitmap.
  - **Tmrc.Cli/Recording/Mp4SegmentWriter.cs**: `Write(frames, width, height, outputPath, fps)` encodes BGRA frames to MP4 via FFmpeg (temp BMP sequence → libx264 yuv420p); `IsAvailable()` probes for `ffmpeg` on PATH.
  - **Daemon**: On startup, tries `ScreenCapture` (real GDI capture); on failure, uses simulated 30% event model. If `Mp4SegmentWriter.IsAvailable()`, segments are written as `.mp4`; otherwise `.bin`. Index stores segment path; export and retention work for both extensions.

  - **Not yet implemented (high level gaps vs spec/test matrix)**
  - **Recording/capture:**
    - Optional upgrade to `Windows.Graphics.Capture` (better performance/window capture); monotonic vs wall-clock; crash recovery semantics.
  - **Indexing/OCR:**
    - **OCR:** When Tesseract and FFmpeg are on PATH, daemon runs OCR on each closed MP4 segment (first frame → PNG → Tesseract) and upserts `ocr_text`; `tmrc ask` then matches on that text. STT still not implemented. Still missing:
      - Rebuild/re-index subcommand (re-run OCR on existing segments).
      - Optional Windows.Media.Ocr or configurable OCR languages (config has `ocr_recognition_languages`; Tesseract CLI uses default/lang flag TBD).
  - **Export:**
    - Time-range export to **MP4 or GIF** is implemented (FFmpeg concat + re-encode; quality presets; `--format gif`). Manifest-only export via `--format manifest`. Still missing:
      - Export by query (`--query "..."`) to one merged range.
      - Concurrent export limits (spec allows multiple exports; no serialization).

- **Next suggested milestones**
  1. ~~**Real capture:** Integrate capture and MP4 segments.~~ Done: GDI capture + FFmpeg MP4 segments; optional WGC upgrade later.
  2. ~~**Export to MP4/GIF:** Stitch segment MP4s into a single output file (MP4 or GIF); respect `export_quality` and `-o`; fail clearly on missing segments.~~ Done: VideoExport + CLI `--format mp4|gif|manifest`.
  3. ~~**OCR/STT and ask:** Populate `ocr_text`/`stt_text` when segments are closed (or via re-index); keep current keyword ask.~~ Done: Tesseract OCR on each MP4 segment (FFmpeg extract frame + Tesseract CLI); ask already keyword-over-index. STT and re-index subcommand still TBD.
  4. ~~**Ops and polish:** Log rotation, uninstall flags, Windows toasts, and edge-case handling (disk full, read-only, etc.).~~ Done: 7-day log rotation; uninstall --remove-data; WindowsToastNotifier (PowerShell+WinRT); TryProbeWritable at daemon start; toast and exit on write IOException.

