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

Planning. Implementation not yet started.
