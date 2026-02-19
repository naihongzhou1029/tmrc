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
  - YAML-based config loader (`config.yaml`) with defaults and overrides for:
    - `sample_rate_ms`, `session`, `capture_mode`, `display`, `audio_enabled`,
      `record_when_locked_or_sleeping`, `storage_root`, `index_mode`,
      `ocr_recognition_languages`, `ask_default_range`, `export_quality`, `log_level`.
  - `storage_root` default: `%USERPROFILE%\.tmrc`.
- **Storage layout & retention**:
  - `storage_root` with:
    - `index/<session>.sqlite` (schema TBD, not yet implemented),
    - `segments/`,
    - `tmrc.pid`, `tmrc.log`.
  - `RetentionManager` with:
    - Max age (days) eviction.
    - Max disk (bytes) eviction (oldest-first).
  - Disk-usage computation for `storage_root`.
- **Time-range parsing**:
  - Absolute: `"YYYY-MM-DD HH:mm:ss"` in local time.
  - Relative helpers: `"now"`, `"1h ago"` (and other units), `"yesterday"`.
- **CLI (Windows)**:
  - `tmrc install` – create storage layout and default config if missing.
  - `tmrc status` – prints basic status (currently `Recording: no`, plus storage root).
  - `tmrc wipe` – clears `segments/` under the configured storage root.
  - `tmrc --version` – prints a Windows dev version (`0.1.0-windows-dev`).
- **Support**:
  - Simple file logger (`tmrc.log`) with log levels.
  - Stub notifier that logs “toast” messages to stderr (Windows toast integration TBD).
- **Test suite**:
  - .NET xUnit suite in `src/test_suite/Tmrc.Tests` covering:
    - Config defaults/overrides and validation.
    - Storage root resolution, install layout, index path helpers, retention behavior, disk usage.
    - Time-range parsing (relative/absolute) semantics.
  - All current tests pass via `./devops.ps1 test`.

Not yet implemented (Windows):

- Screen-capture daemon (Windows.Graphics.Capture or equivalent) and event-based segmenter.
- Media Foundation-based H.264 segment writer and export pipeline (MP4/GIF, quality presets, query-to-range).
- SQLite index schema/manager, OCR/STT integration, `ask` engine and citations.
- Real `record` start/stop semantics, PID file + named-pipe IPC, health/status details.
- Toast notifications via Windows notification APIs.

---

## Development command center (Windows/.NET)

Use a single PowerShell script, `devops.ps1`, as the entry point for local development operations on Windows.

### Prerequisites

- Windows 10 1903+ (ideally Windows 11).
- .NET SDK 8 (the script can install it via `winget` or `choco` if missing).
- Optional:
  - `ffprobe` (for media export test validation).
  - `dotnet-format` (for lint/format workflow).

### Usage

```powershell
./devops.ps1 help
./devops.ps1 setup
./devops.ps1 build
./devops.ps1 test
./devops.ps1 lint
./devops.ps1 record
./devops.ps1 status
./devops.ps1 dump
./devops.ps1 wipe
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
- **`record` / `status` / `dump` / `wipe`**:
  - Call into the Windows CLI (`Tmrc.Cli`) via `dotnet run`.
  - `record` is currently a placeholder until the Windows daemon is implemented.
  - `status` prints basic info (`Recording: no`, storage root).
  - `dump` exports a wide time range via `tmrc export` (not yet implemented; placeholder).
  - `wipe` clears all recordings under `segments/` in the current storage root.
- **`clean`**:
  - Runs `dotnet clean` on `src/Tmrc.sln`.

---

## Known issues / limitations (Windows)

- **Recording not yet implemented on Windows**
  - `tmrc record` and real-time capture are placeholders; there is no running daemon or Media Foundation segment writer yet.
- **Ask/export not yet wired**
  - `tmrc ask` and `tmrc export` are not implemented on Windows; there is no index schema or export pipeline yet.
- **OCR/STT not yet available**
  - No OCR/STT integration; indexing and semantic search are future work on Windows.
- **Toast notifications are stubbed**
  - Notifications are logged to stderr; native Windows toast integration is still pending.

For a more detailed, itemized view of implementation vs plan, see `specs/building_progress.md` and `specs/spec.md` / `specs/test.md`.
