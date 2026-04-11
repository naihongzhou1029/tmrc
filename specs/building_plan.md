# Windows Version: Building Plan

Plan for implementing a **Windows** version of **tmrc** (Time Machine Recall Commander), aligned with the behaviour and semantics defined in [spec.md](spec.md) and validated by [test.md](test.md). The macOS implementation is Swift on Apple Silicon using ScreenCaptureKit, AVFoundation, Vision, and a CLI–daemon model; this document maps each area to Windows equivalents and calls out decisions, risks, and open points.

**Objective:** Deliver the same user-facing behaviour (record → index → search / export) on Windows, with a Windows-native stack. Config schema and CLI surface should stay as close as possible to the macOS version for cross-platform consistency.

---

## 1. Language, runtime, and build

| Aspect | macOS | Windows (choice) | Recommendation / TODO |
|--------|--------|------------------|------------------------|
| **Language** | Swift | **C# / .NET** | Use modern C# targeting .NET 8+ for first-class access to WinRT/Windows APIs (capture, OCR, toast, IPC) and good tooling. |
| **Runtime** | Swift runtime (system) | .NET runtime (SDK or self-contained) | Support both **framework-dependent** and **self-contained** publish; document minimum .NET version (target: **.NET 8**). |
| **Build** | SwiftPM (`swift build`) | `dotnet` CLI / MSBuild | **TODO:** Confirm CI setup (e.g. GitHub Actions `windows-latest` with .NET 8 SDK, VS Build Tools as needed). |
| **Package layout** | Single repo, `Sources/tmrc`, `Tests/tmrcTests` | Same repo: new top-level (e.g. `tmrc-windows/` or `src/Windows/`) or separate solution under `windows/` branch. | **TODO:** Decide: same repo + platform-specific folder, or subfolder per platform with shared spec/config docs. |

**Attention:** The macOS codebase cannot be reused as-is (Swift + Apple frameworks). Windows will be a **separate implementation** sharing only spec, config schema, test matrix, and docs. Any shared logic (e.g. time-range parsing, config validation) would require a shared spec or a small cross-platform layer (e.g. config schema in YAML + shared test vectors).

---

## 2. Paths and storage layout

| Item | macOS | Windows | Notes / TODO |
|------|--------|---------|----------------|
| **Storage root default** | `~/.tmrc/` | `%USERPROFILE%\\.tmrc\\` | Use `%USERPROFILE%\\.tmrc\\` as the default `storage_root` for parity with `~/.tmrc/` and to keep user data in the profile. |
| **Config (dev)** | Project root `config.yaml` | Same: `config.yaml` in repo root when running from repo. | |
| **Config (installed)** | `~/.config/tmrc/config.yaml` (TBD) | `%USERPROFILE%\\.tmrc\\config.yaml` | Default `config.yaml` lives next to data under `storage_root`; allow override via env (e.g. `TMRC_CONFIG`). |
| **Path separators** | `/` | Use `Path.Combine` / `Path.GetFullPath`; never hardcode `\` in logic. | |
| **Home expansion** | `~` → `$HOME` | `~` in config: **TODO:** Expand to `%USERPROFILE%` when parsing `storage_root`. | Implement and test. |
| **Directory layout** | Same as spec: `tmrc.pid`, `tmrc.sock`, `tmrc.log`, `index/<session>.sqlite`, `segments/` | Replace **`tmrc.sock`** with a **named pipe** or **localhost TCP** (see Section 5). Paths: `tmrc.pid`, `tmrc.log`, `index\<session>.sqlite`, `segments\`. | Keep layout identical in spirit; only IPC mechanism differs. |

Spec reference: Section 2 (Storage), Section 9.8 (deterministic paths).

---

## 3. Screen capture

| Aspect | macOS | Windows | Notes / TODO |
|------|--------|---------|----------------|
| **API** | ScreenCaptureKit (SCStream, SCDisplay, SCShareableContent) | **Windows.Graphics.Capture** (WinRT, Windows 10 1903+ / Windows 11) | Use Windows.Graphics.Capture as the primary capture API for display/window capture. Minimum supported OS: **Windows 10 1903+** (practically Win11-first). |
| **Display choice** | `display: main` (default), combined, or index | v1: support `main` (primary monitor) and numeric index (Nth monitor from Windows.Graphics.Capture enumeration). Treat `combined` as unsupported on Windows v1 → fall back to `main` and log a warning. | |
| **Capture mode** | full_screen (default), window, app | v1: support **`full_screen` only** on Windows. Accept `window` / `app` in config but treat them as `full_screen` with a logged warning; plan proper window/app capture for a later phase (spec 1.5). | |
| **Resolution / DPI** | Native (Retina backing scale); test 18 | **TODO:** Per-monitor DPI: capture at raw pixels; document scaling for different DPIs and multi-monitor. Test at 100%, 125%, 150% scaling. | |
| **Frame delivery** | SCStreamOutput, sample buffers at sample_rate_ms | Poll or callback at configured interval; emulate “event-based” by sampling at that rate. **TODO:** Decide callback vs timer-based poll; match segmenter semantics (spec 1.1–1.2). | |
| **Permission** | Screen Recording permission; prompt before start; revoke → toast, sync, quit (spec 1.8) | No formal “screen recording” permission; capture may fail if session is locked or restricted. Treat **“cannot start capture”** or **repeated capture errors** as fatal: stop recording, sync artifacts, and exit. **User-facing messages should describe the concrete problem (e.g. “screen capture failed” / “screen capture stopped”) and avoid talking about “permissions”.** Document that we do not run under session 0 (no headless capture). | |
| **Lock / sleep** | `record_when_locked_or_sleeping` (default false) | Detect session lock (e.g. WinRT session state / WTS APIs) and sleep; when `false` (default), stop capture and pause recording while locked/sleeping, then resume as a new run after unlock/wake. When `true`, attempt to keep capturing, subject to what Windows allows; log clearly either way. | |

Spec reference: Section 1 (Recording). Test items: 4–5 (segment boundaries), 9–10 (display, capture mode), 14–15 (permission), 18 (resolution).

---

## 4. Audio (optional)

| Aspect | macOS | Windows | Notes / TODO |
|------|--------|---------|----------------|
| **Default** | Off | Off | |
| **When enabled** | Continuous; 3 h segments for export (MP3) | **TODO:** Use **WASAPI** loopback capture (default device) or **Windows.Media.Capture**. Segment into 3 h chunks; export as MP3. Format/sample rate TBD; match spec 1.6. | |
| **Microphone** | If enabled, request Mic permission | **TODO:** If we add microphone (not in current spec), document permission and fallback. Spec says “audio” for export; confirm whether “audio” means system loopback only or also mic. | |

Spec reference: Section 1.6, 2 (audio segment layout). Test: 12.

---

## 5. Daemon and CLI–daemon communication

| Aspect | macOS | Windows | Notes / TODO |
|------|--------|---------|----------------|
| **Process model** | Two processes: CLI spawns daemon; daemon runs until `record --stop` or termination (spec 6.1) | Same: one background “daemon” process; CLI starts/stops it as a **detached background process** (no window, e.g. `CREATE_NO_WINDOW`). It is **not** a Windows Service and does **not** auto-start on boot. | |
| **Discovery** | PID file under `storage_root` (spec 6.2) | Same: `tmrc.pid` under storage root; CLI reads PID and checks process exists (e.g. OpenProcess or equivalent). | |
| **CLI → daemon** | Unix domain socket (e.g. `tmrc.sock`) | **No Unix socket on Windows.** Use a **named pipe** for CLI–daemon RPC, e.g. `\\\\.\\pipe\\tmrc-<user>-<session>`, with name derived from storage_root/session and scoped to the current user. | |
| **Start daemon** | `tmrc record` passes `--daemon`, storage root, session, config path | Same; Windows daemon parses same args and writes PID file, then opens pipe (or listens) for commands. | |
| **Stop daemon** | SIGTERM; daemon syncs and exits | **TODO:** No SIGTERM. Options: (1) CLI sends “stop” over pipe, daemon exits; (2) CLI uses TerminateProcess after graceful message. Prefer (1) so daemon can sync before exit; (2) as fallback with short timeout. | |
| **Single instance** | One daemon per user (PID file); “already running” message (spec 6.6) | Same: if PID file exists and process exists, refuse to start second daemon; same user-facing message. | |

Spec reference: Section 6 (CLI & Daemon). Test items: 58–61 (daemon start/stop/discovery).

---

## 6. Configuration and logging

| Aspect | macOS | Windows | Notes / TODO |
|------|--------|---------|----------------|
| **Format** | YAML (`config.yaml`) | Same; use a YAML parser for .NET (e.g. YamlDotNet) or equivalent in C++/Rust. | |
| **Keys** | As in repo `config.yaml`: sample_rate_ms, display, capture_mode, audio_enabled, record_when_locked_or_sleeping, session, storage_root, index_mode, ocr_*, search_default_range, export_quality | Keep same keys and semantics; add Windows-specific only if needed (e.g. capture API choice). **TODO:** Validate `storage_root` and path expansion on Windows. | |
| **Log file** | Single file `storage_root/tmrc.log`; 7-day rotation (spec 2, 6.5) | Same path; rotation: **TODO:** Implement in-process (e.g. by date in filename or size+date); no logrotate. Document rotation policy. | |
| **Log level** | Default info; configurable | Same. | |

Spec reference: Section 6.4–6.5. Test items: 1–3, 6–7, 9–11, 13, 19–20, 30–34, 66–69, 71.

---

## 7. Segment writing and encoding

| Aspect | macOS | Windows | Notes / TODO |
|------|--------|---------|----------------|
| **Segment format** | MP4 (AVAssetWriter, H.264/HEVC) | **Media Foundation (MF), H.264 MP4** | Use Media Foundation for segment writing and reading on Windows; target H.264 for compatibility (spec 2.6). GIF support can be implemented separately (simple encoder or using MF pipelines where feasible). | |
| **Event-based segmentation** | EventSegmenter + SegmentWriter; flush when next frame has no events (spec 1.2) | Reuse same logic: sample at `sample_rate_ms`, segment boundaries by “no events in next frame”. **TODO:** Ensure monotonic vs wall-clock time (spec 8.5) and crash recovery (remove incomplete segments on start, spec 8.4). | |
| **Segment path** | e.g. `segments/YYYY-MM-DD/segment_<id>.<ext>` (spec 2) | Same layout; use `YYYY-MM-DD` and consistent naming. | |

Spec reference: Section 1.1–1.2, 2, 8.4–8.5. Test items: 4–5, 16–17, 24–26, 29, 49, 80.

---

## 8. Index and OCR

| Aspect | macOS | Windows | Notes / TODO |
|------|--------|---------|----------------|
| **Index storage** | SQLite per session: `index/<session>.sqlite` (spec 2, 3.6) | Same; use **SQLite** (e.g. Microsoft.Data.Sqlite or sqlite3). **TODO:** Reuse or port schema from macOS (IndexSchema); keep segment id, time range, OCR text, STT, optional embedding refs. | |
| **OCR engine** | Vision `VNRecognizeTextRequest`; languages en-US, zh-Hant, zh-Hans (spec 3.2) | **Tesseract** (offline OCR engine) with language packs for `en-US`, `zh-Hant`, `zh-Hans` | Bundle or depend on Tesseract and ship the required language data files. Keep `ocr_recognition_languages` in config; map entries to installed Tesseract langs and fail clearly if a requested lang is missing. | |
| **When to index** | Real-time as segments close (spec 3.1) | Same; run OCR after each segment is written. | |
| **Failure** | Partial index allowed; notify user (toast/status) (spec 3.7) | Same; toast on Windows (see Section 11). | |
| **Rebuild index** | Subcommand from segments (spec 3.8) | Same; `tmrc rebuild-index` (or equivalent) rebuilds from segment files. | |

Spec reference: Section 3. Test items: 29, 35–38, 82.

---

## 9. Recall: Search and export

| Aspect | macOS | Windows | Notes / TODO |
|------|--------|---------|----------------|
| **Time range parser** | Relative (“1h ago”) and absolute; local time (spec 4.1, 5.1, 8.5) | **TODO:** Port or reimplement parser; use system local time and same format. Test items 41–42. | |
| **Search** | Keyword/semantic search, citations, no/multiple matches (spec 4) | Same behaviour; keyword search from OCR text; optional embeddings/LLM later. **TODO:** Citation format YYYY-MM-DD HH:MM:SS (spec 4.4). | |
| **Export** | Stitch segments, H.264 MP4 / GIF; quality presets; `--from`/`--to`/`--query` (spec 5) | Use **Media Foundation** to decode/concat/encode H.264 MP4 exports. For GIF, implement either a lightweight encoder on top of decoded frames or a secondary pipeline; keep the CLI surface the same as macOS but document any Windows-specific GIF limitations. Missing segment → fail with clear message (spec 9.4, test 50). Concurrency: allow multiple exports (spec 5.7). | |
| **Export while recording** | Allowed; only read closed segments (spec 5.8) | Same; ensure no open file conflict (e.g. write to temp then move, or share-read access). | |

Spec reference: Section 4–5, 9. Test items: 39–57.

---

## 10. Notifications (toast)

| Aspect | macOS | Windows | Notes / TODO |
|------|--------|---------|----------------|
| **When** | Permission revoked, low disk, etc. (spec 1.8, 2.4) | Same cases. Use **Windows Toast Notifications** via WinRT (`ToastNotificationManager`). `tmrc install` is responsible for setting up an App User Model ID and (if needed) a Start Menu shortcut so toasts appear under a stable app identity. | |

Spec reference: Section 1.8, 2.4, 3.7. Test items: 15, 27.

---

## 11. Install / uninstall and lifecycle

| Aspect | macOS | Windows | Notes / TODO |
|------|--------|---------|----------------|
| **Install** | `tmrc install`: create dirs, default config (spec 8.1) | Same; create storage_root, index, segments; write default config if missing. **TODO:** Optionally add to PATH (user or system) or create Start Menu shortcut; document. | |
| **Uninstall** | `tmrc uninstall`; optional `--remove-data` (spec 8.1) | Same; stop daemon, then optionally remove dirs. | |
| **Graceful shutdown** | SIGTERM/SIGINT → sync, exit (spec 8.3) | **TODO:** On “stop” command via pipe (or console Ctrl+C if daemon has console in dev): flush segments, close index, remove PID/pipe, exit. If daemon is a Service, handle Service stop event. | |
| **Crash recovery** | New session; delete/ignore incomplete segments (spec 8.4) | Same; on startup, remove or ignore partial segment files. | |
| **Version** | `tmrc --version`; same in logs (spec 10.3) | Same. | |

Spec reference: Section 8. Test items: 74–81.

---

## 12. Security and permissions

| Aspect | macOS | Windows | Notes / TODO |
|------|--------|---------|----------------|
| **Data at rest** | Optional encryption; disabled by default (spec 7.1) | Same; out of scope for v1; document. | |
| **Access control** | Rely on filesystem (spec 7.2) | Same; storage under user profile; no extra ACLs. **TODO:** Ensure created dirs/files are not world-readable. | |
| **Read-only storage** | Fail fast (spec 9.3, 7.2) | Same; check writable before start and on first write. | |

Spec reference: Section 7, 9. Test items: 71–73.

---

## 13. Development and test workflow

| Aspect | macOS | Windows | Notes / TODO |
|------|--------|---------|----------------|
| **Entry script** | `devops.sh` (setup, build, test, lint, record, status, dump, wipe, clean) | Provide **PowerShell** script `devops.ps1` with equivalent commands: `help`, `setup` (check .NET/VS, optional ffprobe), `build`, `test`, `lint`, `record`, `status`, `dump`, `wipe`, `clean`. | |
| **Tests** | Swift tests; many unit, some E2E (test.md) | **TODO:** Port or reimplement tests per test.md; mark tests that need real capture, permissions, or long run (E2E/soak). CI: run unit tests on Windows runner; E2E optional or manual. | |
| **Lint** | swiftlint | **TODO:** Choose linter (e.g. StyleCop, EditorConfig, or Roslyn analyzers for C#). | |

Spec reference: Section 10. Test items: all of test.md; many are platform-agnostic (config, paths, index, search, export logic).

---

## 14. Phased implementation (suggested)

- **Phase 1 – Foundation**  
  Language/runtime choice; repo layout; paths and config loader; storage root and directory layout; PID file and daemon discovery; CLI skeleton (`record --start/--stop`, `status`, `install`, `uninstall`); logging and rotation.  
  **Deliverable:** CLI that can “start” and “stop” a daemon (no real capture yet) and report status.

- **Phase 2 – Capture and segments**  
  Screen capture API (WinRT or DDA); event-based segmenter; segment writer (MP4); retention and crash recovery; low-disk and “permission” failure handling; toast for failures.  
  **Deliverable:** Daemon records screen to segments under storage_root; retention and single-instance enforced.

- **Phase 3 – Index and OCR**  
  SQLite schema; OCR integration (post-segment); rebuild-index; search (keyword search) and export (stitch by time range).  
  **Deliverable:** `tmrc search` and `tmrc export --from/--to` working with real segments and index.

- **Phase 4 – Parity and polish**  
  Query-to-export; quality presets; GIF export; time-range parser edge cases; config location (installed); devops.ps1; test matrix (unit + critical E2E); documentation and known issues.

---

## 15. Open decisions and TODOs (summary)

Items that need your confirmation or choice before or during implementation:

1. **Language/runtime:** **C# / .NET 8+** (chosen; Section 1).  
2. **Repo layout:** Same repo with `tmrc-windows/` (or similar) vs separate repo (Section 1).  
3. **Storage root default:** `%USERPROFILE%\\.tmrc\\` (chosen; Section 2).  
4. **Config location (installed):** `%USERPROFILE%\\.tmrc\\config.yaml` (chosen; Section 2).  
5. **Capture API:** **Windows.Graphics.Capture**, min Windows 10 1903+ (Section 3).  
6. **Display/capture mode:** v1 = `display: main`/index + `capture_mode: full_screen` only (Section 3).  
7. **Capture failure semantics on Windows:** Treat “cannot start capture” / repeated capture errors as fatal; message uses concrete problem description, not “permission” wording (Section 3).  
8. **Lock/sleep detection:** Detect lock/sleep and pause recording when `record_when_locked_or_sleeping` is false; resume as a new run on unlock/wake (Section 3).  
9. **CLI–daemon IPC:** **Named pipe** for CLI–daemon RPC (Section 5).  
10. **Daemon process type:** Detached background process (not a Windows Service; Section 5).  
11. **Video encode/decode:** **Media Foundation (H.264 MP4)** for segments/export; GIF via a simple encoder or secondary pipeline (Sections 7, 9).  
12. **OCR engine:** **Tesseract** with language packs for en-US / zh-Hant / zh-Hans (Section 8).  
13. **Toast notifications:** **WinRT toast** via `ToastNotificationManager`; set up AppID/shortcut in `tmrc install` (Section 10).  
14. **Devops script:** `devops.ps1` PowerShell entrypoint with `help/setup/build/test/lint/record/status/dump/wipe/clean` (Section 13).  

After these are decided, the plan can be updated and implementation can proceed phase by phase with minimal rework.
