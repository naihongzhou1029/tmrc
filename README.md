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

- **First target:** macOS on **Apple Silicon (M-Series)**.
- **Language:** **Swift** (native SDK access: ScreenCaptureKit, AVFoundation, Vision, etc.).
- **Later:** Other platforms/systems as needed.

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

In progress. Implemented: CLI (record start/stop/status, install, uninstall, status, ask, export, rebuild-index), config (YAML + defaults), storage layout and retention, daemon process (start/stop; capture loop with ScreenCaptureKit), SQLite index schema and keyword search, time-range parser, ask engine (empty index, no-matches, citations), **export (stitch MP4/GIF, --from/--to/--query, missing-segment error, quality presets)**. Recording pipeline: ScreenCaptureKit capture (main/combined display), event-based segmenter, segment writer (AVAssetWriter H.264 MP4), segment index upsert and retention eviction; **OCR (Vision) per segment after write**; **permission-revoked detection and toast**; **low-disk check and toast**; **crash recovery (remove incomplete segments on start)**. Log file (single file, 7-day rotation), debug/version in logs. Pending: audio capture, window/app capture mode, optional Unix socket IPC.

---

## Development command center

Use a single script, `devops.sh`, as the entry point for local development operations.

### Prerequisites

- macOS (first target), ideally Apple Silicon.
- Xcode Command Line Tools.
- Swift toolchain available in `PATH`.
- Optional: `ffprobe` (for media export test validation), `swiftlint` (for lint workflow).

### Usage

```bash
./devops.sh help
./devops.sh setup
./devops.sh build
./devops.sh test
./devops.sh lint
./devops.sh record
./devops.sh status
./devops.sh dump
./devops.sh wipe
./devops.sh release <vX.Y.Z>
./devops.sh clean
```

### Command notes

- `setup` / `check-env`: validates development toolchain and optional tools; prints the full environment checklist. Only this command shows the `[ok]` / `[warn]` lines.
- `build`: runs `swift build` (requires `Package.swift`). Runs setup checks silently first.
- `test`: runs `swift test` (requires `Package.swift`). Runs setup checks silently first.
- `lint`: runs `swiftlint` when installed. Runs setup checks silently first.
- `record`: toggles recording (start if stopped, stop if running). Uses the built `tmrc` binary; no setup output or build log.
- `status`: prints recording status, storage path, disk usage, and retention policy. Uses the built binary; no setup output or build log.
- `dump`: exports all recordings to a single timestamped MP4 in the project root (`tmrc_dump_YYYY-MM-DD_HH-MM-SS.mp4`). Uses the built binary; no setup output or build log.
- `wipe`: removes all segment files and clears the index; the daemon (if running) keeps running. Uses the built binary; no setup output or build log.
- `release`: builds for production (`-c release`) and creates a zip bundle in the `dist/` directory. If GitHub CLI (`gh`) is available, it offers to tag and upload the release.
- `clean`: runs `swift package clean` (requires `Package.swift`). Does not run setup.

### Built executable

After `swift build`, the native binary is produced under the Swift Package Manager build directory (not committed; see `.gitignore`). For a **debug** build it is at:

```
.build/arm64-apple-macosx/debug/tmrc
```

You can run it directly (e.g. `.build/arm64-apple-macosx/debug/tmrc --version`) or use `swift run tmrc`. For an optimized **release** build, run `swift build -c release`; the binary is then at `.build/arm64-apple-macosx/release/tmrc`.

