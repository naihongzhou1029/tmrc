# Time Machine Recall Commander (tmrc)

A command-line tool that records your screen (and optionally audio), indexes the content, and lets you recall the past—either by exporting video/GIF or by asking questions and getting text replies. No GUI; CLI only.

**Executable name:** `tmrc`

---

## Goals

- **Record** what you see and do on the machine (screen capture; optional audio).
- **Index** the recording so it can be searched (OCR, speech-to-text, optionally embeddings).
- **Recall** in two ways:
  1. **Export** — User requests a time range (or a query) and gets a **GIF** or **MP4** file.
  2. **Ask** — User asks in natural language and gets **text** replies (no GUI).

Think “Rewind-like,” but CLI-only and self-hosted/local-first.

---

## Platform & language

- **Current implementation:** Windows (CLI + background process).
- **Language/runtime:** **C# / .NET 8**.
- **Later:** Other platforms/systems as needed, reusing the same CLI and spec where possible.

---

## Architecture (high level)

1. **Background recorder (daemon / launch agent)**
   - Uses **ScreenCaptureKit** (and optionally audio) to capture.
   - Writes to a local store: time-chunked frames/segments plus a sidecar index.

2. **Indexing pipeline**
   - OCR and/or speech-to-text on captured content.
   - Optional: embeddings for semantic search.
   - Enables search by time range or by natural-language query.

3. **CLI**
   - `tmrc record` — Start/stop or configure recording (or “ensure daemon is running”).
   - `tmrc ask "..."` — Natural-language question → text answer (and optionally time references for export).
   - `tmrc export` — Export a time range or query-matched segment to **MP4** or **GIF** (e.g. `--from`, `--to`, `--format`, `-o`).

---

## Non-goals (for now)

- No graphical UI; all interaction via the `tmrc` CLI.
- No requirement to support Intel Macs or other OSes in the first version.

---

## Name

- **Full name:** Time Machine Recall Commander  
- **Short name / binary:** **tmrc**  
- Chosen to avoid collision with existing CLIs (e.g. `tmc` used by TestMyCode and WoT ThingModel Catalogs).

---

## Status

**In progress (Windows/.NET implementation).**

Implemented so far:

- **Core config**:
  - INI-based config loader (`config.ini`) with defaults and overrides for:
    - `sample_rate_ms`, `session`, `capture_mode`, `display`, `audio_enabled`,
      `record_when_locked_or_sleeping`, `storage_root`, `retention_max_age_days`, `retention_max_disk_bytes`,
      `index_mode`,
      `ocr_recognition_languages`, `ask_default_range`, `export_quality`, `log_level`.
  - `storage_root` default: `%USERPROFILE%\.tmrc`.
- **Storage layout & retention**:
  - `storage_root` with:
    - `index/<session>.sqlite` (segment index with id, time range, path, ocr_text, stt_text),
    - `segments/`,
    - `tmrc.pid`, `tmrc.log`.
  - `RetentionManager` with:
    - Max age (days) and max disk (bytes) eviction (oldest-first); configurable via `retention_max_age_days` and `retention_max_disk_bytes` (defaults 30 days, 50 GB).
    - When segments are evicted, the index is pruned so ask/export and reindex only reference existing files.
  - Disk-usage computation for `storage_root`.
- **Time-range parsing**:
  - Absolute: `"YYYY-MM-DD HH:mm:ss"` in local time.
  - Relative helpers: `"now"`, `"1h ago"` (and other units), `"yesterday"`.
- **CLI (Windows)**:
  - `tmrc install` – create storage layout and default config if missing.
  - `tmrc uninstall [--remove-data]` – stop the daemon if running; with `--remove-data`, delete the storage root.
  - `tmrc status` – prints basic status (Recording yes/no, storage root, disk usage).
  - `tmrc wipe` – clears `segments/` under the configured storage root.
  - `tmrc reindex [--force]` – re-runs OCR on existing MP4 segments in the index (Tesseract + FFmpeg required). By default only segments with no OCR text are processed; `--force` re-indexes all.
  - `tmrc --version` – prints a Windows dev version (`0.1.0-windows-dev`).
- **Support**:
  - Simple file logger (`tmrc.log`) with log levels (debug, info, warn, error).
  - **Debug mode:** `tmrc --debug <command>` or `TMRC_DEBUG=1` enables verbose logging: daemon uses Debug log level and emits frame/segment activity. Useful for support and troubleshooting.
  - Windows toast notifications via WinRT on recording start/stop events.
  - **System tray icon**: when the daemon is recording, a tray icon appears in the notification area with a right-click context menu providing:
    - **Status** — shows current recording info (PID, uptime, segment count, disk usage) in a dialog.
    - **Open Storage Folder** — opens `storage_root` in Explorer.
    - **Stop Recording** — gracefully shuts down the daemon.
- **Test suite**:
  - .NET xUnit suite in `src/test_suite/Tmrc.Tests` covering:
    - Config defaults/overrides and validation.
    - Storage root resolution, install layout, index path helpers, retention behavior, disk usage.
    - Time-range parsing (relative/absolute) semantics.
  - All current tests pass via `./devops.ps1 test`.

Implemented (Windows, this phase):

- **Real screen capture** via GDI BitBlt; event-based segmenter with frame-diff detection.
- **MP4 segment writer** via FFmpeg (BMP sequence → libx264); segments stored as `.mp4` when FFmpeg is on PATH, else `.bin` placeholder.

Implemented (Windows, export):

- **Export to MP4/GIF:** `tmrc export (--from <expr> --to <expr> | --query "..." [--since <expr>] [--until <expr>]) [-o <path>] [--format mp4|gif|manifest]`. Default format is **mp4**. When `-o` is omitted, output is written to the current directory with a generated filename (session + time range). Time-range export uses the given range; **query export** finds segments matching the query (same keyword search as `tmrc ask`), merges their time range (earliest start to latest end), and exports that span. Default scope for `--query` is last 24h; use `--since`/`--until` to override. FFmpeg stitches segment MP4s into a single file; quality presets (low/medium/high) from config `export_quality`. Use `--format manifest` to write a text manifest of segment paths only.

Implemented (Windows, indexing/ask):

- **OCR:** When **Tesseract** and FFmpeg are on PATH, the recorder daemon runs OCR on the first frame of each closed MP4 segment and stores text in the index (`ocr_text`). Languages are configurable via `config.ini` → `ocr_recognition_languages` (BCP 47 / locale, e.g. `en-US`, `zh-Hant`, `zh-Hans`); values are mapped to Tesseract `-l` codes (eng, chi_tra, chi_sim, jpn, kor, or pass-through). Default: `["en-US", "zh-Hant", "zh-Hans"]`. `tmrc ask` matches queries against this text (keyword search). Without Tesseract, segments are still recorded and export works; ask has no text to search.
- **Reindex:** `tmrc reindex [--force]` re-runs OCR on segments already in the index using the same config languages (improves UX without re-recording; requires Tesseract and FFmpeg).

Not yet implemented (Windows):

- Optional upgrade to Windows.Graphics.Capture; Media Foundation–based H.264 (or keep FFmpeg).
- STT (speech-to-text); optional semantic/LLM for ask.

---

## Development command center (Windows/.NET)

Use a single PowerShell script, `devops.ps1`, as the entry point for local development operations on Windows.

### Prerequisites

- Windows 10 1903+ (ideally Windows 11).
- .NET SDK 8 (the script can install it via `winget` or `choco` if missing).
- **FFmpeg** (on PATH): used for MP4 segment encoding during recording and for export stitching. Without it, segments are stored as `.bin` and video export is unavailable.
- Optional:
  - **Tesseract** (on PATH): enables OCR on each segment so `tmrc ask` can search recorded text.
  - `ffprobe` (for media export test validation).
  - `dotnet-format` (for lint/format workflow).

### Usage

```powershell
./devops.ps1 help
./devops.ps1 setup
./devops.ps1 build
./devops.ps1 test
./devops.ps1 lint
./devops.ps1 clear-tests
./devops.ps1 record
./devops.ps1 status
./devops.ps1 dump
./devops.ps1 wipe
./devops.ps1 reindex
./devops.ps1 publish
./devops.ps1 release <vX.Y.Z>
./devops.ps1 clean
```

### Command notes

- **`setup` / `check-env`**:
  - Validates Windows + .NET SDK and optional tools.
  - Attempts to auto-install .NET SDK 8 if missing and adds common `dotnet` install paths to `PATH`.
  - Only this command shows the `[ok]` / `[warn]` lines.
- **`build`**:
  - Runs `dotnet build src/Tmrc.sln`.
  - Runs setup checks silently first.
- **`test`**:
  - Runs `dotnet test src/Tmrc.sln` (executes `Tmrc.Tests` in `src/test_suite`).
  - Runs setup checks silently first.
- **`lint`**:
  - Runs `dotnet-format` on the solution when installed.
- **`clear-tests`**:
  - Clears all values in the **Pass** column of `specs/test.md`.
  - Keeps all other test table content unchanged (`Actual Result`, action steps, expected results, etc.).
- **`record` / `status` / `dump` / `wipe`**:
  - Call into the Windows CLI (`Tmrc.Cli`) via `dotnet run`.
  - `record` starts the recorder daemon (or reports already in progress).
  - `status` prints basic info (Recording yes/no, storage root, disk usage).
  - `dump` exports a wide time range to a single MP4 via `tmrc export --from "1000d ago" --to now -o <path>` (requires FFmpeg and MP4 segments).
  - `wipe` clears all recordings under `segments/` in the current storage root.
- **`reindex`**:
  - Re-runs OCR on existing segments in the index (requires Tesseract and FFmpeg).
- **`publish`**:
  - Builds a self-contained single-file executable into the `publish/` directory.
- **`release`**:
  - Builds for production and creates a zip bundle in the `dist/` directory. If GitHub CLI (`gh`) is available, it offers to tag and upload the release.
- **`clean`**:
  - Runs `dotnet clean` on `src/Tmrc.sln`.

For a more detailed, itemized view of implementation vs plan, see `specs/building_progress.md` and `specs/spec.md` / `specs/test.md`.
