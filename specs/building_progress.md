## Windows/.NET build progress

- **Repo layout**
  - Swift/macOS package (`Package.swift`, `Sources/`, `Tests/tmrcTests/`, `devops.sh`) **removed**.
  - New `.NET`-based Windows implementation lives under `src/`:
    - `src/src/Tmrc.Core` – core library.
    - `src/src/Tmrc.Cli` – CLI executable.
    - `src/test_suite/Tmrc.Tests` – xUnit test suite.
  - `devops.ps1` is the single entry point for setup/build/test on Windows.

- **Tooling**
  - `devops.ps1 setup`:
    - Verifies Windows, checks/installs **.NET SDK 8**, wires `dotnet` into `PATH` if needed.
    - Checks for `config.yaml`, `ffprobe` (optional), and `dotnet-format` (optional).
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
    - Simple file logger with log levels (debug/info/warn/error).
  - `Support/Notifier`:
    - `INotifier` interface and `NoopNotifier` (writes toast messages to stderr only for now).

- **CLI (Tmrc.Cli)**
  - `Program.cs`:
    - Commands: `record`, `status`, `export`, `ask`, `install`, `uninstall`, `wipe`, `--version`.
    - Current behavior:
      - `--version` prints `TmrcVersion.Current`.
      - `install`:
        - Loads config from `config.yaml` in current directory.
        - Uses `StorageManager.EnsureLayout` on `storage_root`.
      - `status`:
        - Loads config and prints:
          - `Recording: no` (placeholder, daemon not implemented yet).
          - `Storage root: <path>`.
      - `wipe`:
        - Clears and recreates `segments/` under current `storage_root`.
      - `record`, `export`, `ask`:
        - Placeholders (print "not yet implemented on Windows").

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
  - **Current test status**:
    - `devops.ps1 test` → **27 tests, all passing, 0 failures.**

- **Not yet implemented (high level gaps vs spec/test matrix)**
  - **Recording/daemon:**
    - No Windows recorder daemon yet (no `Windows.Graphics.Capture`, no PID/pipe IPC).
    - No event-based segmenter or Media Foundation H.264 segment writer.
  - **Indexing/OCR:**
    - No SQLite index schema or manager.
    - No OCR integration (e.g. Tesseract) or STT.
    - No rebuild/re-index commands.
  - **Ask/export:**
    - No keyword/semantic search over indexed text.
    - No export engine (stitching segments, MP4/GIF output, quality presets).
    - No handling of missing segments or concurrent exports.
  - **CLI/daemon semantics & ops:**
    - `record` is a placeholder (no start/stop/status of a real daemon).
    - No named-pipe IPC, no `tmrc.pid` lifecycle, no log rotation.
    - No uninstall behavior beyond messaging.
  - **Notifications & edge cases:**
    - Toasts currently go to stderr; no WinRT toast integration.
    - No explicit handling for disk-full, read-only storage, overlapping segments, long sessions, soak tests, etc.

- **Next suggested milestones**
  1. Implement daemon/IPC skeleton:
     - Named-pipe server, PID file, `record --start/--stop`, `status`.
  2. Add segmenter + dummy segment files:
     - Event-based boundaries, retention integration; tests for segment boundary behavior.
  3. Introduce SQLite index + basic ask:
     - Schema + keyword search; tests for index create/read and ask no-results/multi-results.
  4. Implement export pipeline:
     - Time-range selection, stitching of dummy segments, MP4 output; tests for export rows in `specs/test.md`.

