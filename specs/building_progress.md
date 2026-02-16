# Building progress: tmrc

This file tracks implementation progress against the plan derived from `spec.md` and `README.md`. Use it to resume work and to know what is done vs pending. Validate behaviour with the test matrix in `specs/test.md`.

**Last synced:** After commit `6574c56` (feat(export): segment export, OCR pipeline, rebuild-index, daemon resilience). Export is full implementation (stitch MP4/GIF, --query, missing-segment error, quality); OCR runs after each segment write; permission-revoked and low-disk trigger toast + exit; crash recovery removes incomplete segments on start. Unit tests added for Export, Ask, TimeRange, Segmenter, Index. Not all plan items implemented (audio, window/app capture, Unix socket). Index build failure toast added in follow-up.

---

## 1. Recording & Capture

| Item | Status | Notes |
|------|--------|--------|
| Event-based segments, sample_rate_ms (32.2 ms default) | Done | Config + EventSegmenter + DaemonRunner loop |
| Segment boundaries (flush on idle frame) | Done | EventSegmenter.pushFrame / flushPending |
| Display option (main / combined) | Done | ScreenCaptureService + config.display |
| capture_mode (full_screen / window / app) | Pending | Config key exists; capture is display-only, no window/app filter yet |
| Audio recording (audio_enabled, 3h segments, MP3) | Pending | Config only; no audio in capture or export |
| record_when_locked_or_sleeping | Pending | Config only; behaviour not enforced |
| Permission before start | Done | Capture fails until Screen Recording granted; daemon exits on start error |
| Permission revoked mid-session → toast, sync, quit | Done | SCStreamDelegate didStopWithError + Notifier + signalReceived |
| Session identity, multi-session, graceful shutdown | Done | session in config/CLI; SIGTERM/SIGINT flush and exit |
| ScreenCaptureKit capture | Done | ScreenCaptureService (main/combined display) |
| Segment writer (MP4) | Done | SegmentWriter (AVAssetWriter H.264) |

---

## 2. Storage & Retention

| Item | Status | Notes |
|------|--------|--------|
| storage_root default ~/.tmrc/, configurable | Done | ConfigLoader + Installer |
| Directory layout (index/, segments/, tmrc.pid, tmrc.log) | Done | StorageManager; segments flat `segments/<id>.mp4` |
| Retention (max age, max disk, ring-buffer) | Done | RetentionManager; evict after each segment write |
| Disk full / low space → sync, toast, exit | Done | DaemonRunner checks freeSpace() each loop; Notifier + exit |
| Usage report | Done | tmrc status shows disk usage |
| Unix socket (tmrc.sock) | Pending | Path defined; not created or used for CLI–daemon IPC |

---

## 3. Indexing Pipeline

| Item | Status | Notes |
|------|--------|--------|
| Index per session (SQLite in index/) | Done | IndexSchema + IndexManager |
| Schema (id, time range, ocrText, sttText, filePath, status) | Done | Segments written with status "pending"; ocrText from OCR pipeline, sttText nil |
| OCR (Vision VNRecognizeTextRequest, ocr_recognition_languages) | Done | OCRService + DaemonRunner after segment write |
| OCR granularity (per_segment_summary etc.) | Done | Per-segment summary in DaemonRunner |
| Speech-to-text | Pending | Not implemented |
| Embeddings (Advanced mode) | Pending | Spec 3.5 still open; not implemented |
| Index build failure → partial index, notify user | Done | OCR failure leaves status pending; toast via Notifier in DaemonRunner |
| Rebuild index from segments (subcommand/flag) | Done | tmrc rebuild-index |
| Re-index idempotency | Done | Rebuild overwrites via upsert |

---

## 4. Recall: Ask

| Item | Status | Notes |
|------|--------|--------|
| Query scope (ask_default_range, --since, --until) | Done | TimeRangeParser + AskEngine |
| Keyword search (OCR/STT text) | Done | IndexManager.search (LIKE); OCR text populated per segment after write |
| Template answer, citations (YYYY-MM-DD HH:MM:SS, segment ref) | Done | AskEngine |
| No results / empty index messaging | Done | AskEngine |
| Multiple matches, ranking | Done | By time; limit 50 |

---

## 5. Recall: Export

| Item | Status | Notes |
|------|--------|--------|
| --from / --to (absolute and relative), -o | Done | ExportCommand parses; ExportEngine resolves range/query, stitches MP4/GIF |
| --query (merged range) | Done | ExportEngine.resolveQueryRange + export |
| Stitch multiple segments → one MP4/GIF | Done | ExportEngine exportMP4 / exportGIF |
| Missing segment → fail with clear message | Done | ExportError.missingSegment(id, path) |
| Export format (MP4/GIF), quality levels | Done | AVAssetExportSession preset; GIF via ImageIO |
| Output overwrite, concurrent exports | Done | Overwrite by default; no daemon queue |

---

## 6. CLI & Daemon

| Item | Status | Notes |
|------|--------|--------|
| Daemon process (tmrc record --start/--stop, PID file) | Done | DaemonManager + DaemonEntry |
| Daemon already running → clear message | Done | RecordCommand |
| tmrc record --status, tmrc status | Done | StatusCommand, disk usage |
| config.yaml (project root / ~/.config/tmrc), sample_rate_ms etc. | Done | ConfigLoader, TMRCConfig |
| Log file (storage_root/tmrc.log, 7-day rotation) | Done | Logger |
| Single daemon instance (PID file) | Done | DaemonManager.isRunning |
| --version | Done | TMRCVersion; Main + subcommands |
| --debug / TMRC_DEBUG | Done | Logger.configure(debugEnabled:) |

---

## 7. Operations & Observability

| Item | Status | Notes |
|------|--------|--------|
| tmrc install (dirs, default config) | Done | Installer |
| tmrc uninstall (stop daemon, optional --remove-data) | Done | UninstallCommand |
| Graceful shutdown (SIGTERM/SIGINT → flush, exit) | Done | DaemonEntry + DaemonRunner flushPending |
| Version in logs | Done | Logger includes TMRCVersion.current |
| Crash recovery (new session, ignore partial segments) | Done | DaemonEntry.removeIncompleteSegments (< 1KB) on start |
| Monotonic vs wall-clock in index/export | Done | IndexSegment has both; segmenter/writer use them |

---

## 8. Security & Edge Conditions

| Item | Status | Notes |
|------|--------|--------|
| Read-only storage_root → fail fast | Done | ensureWritable at daemon start |
| Data at rest encryption | Pending | Optional per spec; not implemented |
| Deterministic paths (no binary-path dependency) | Done | storage_root, config path from env/defaults |

---

## Summary: Done vs Pending

- **Done:** CLI (record, ask, export, install, uninstall, status, rebuild-index), config (YAML + defaults), daemon (start/stop, ScreenCaptureKit, event segmenter, segment writer), storage layout and retention, SQLite index and keyword search, time-range parsing, ask engine and citations, **export (stitch MP4/GIF, --query, missing-segment error, quality)**, **OCR pipeline (Vision, per-segment)**, **permission-revoked (stream delegate + toast + exit)**, **disk-full check + toast**, **index build failure toast**, **crash recovery (remove incomplete segments on start)**, logging (file, rotation, version, debug).
- **Pending (lower impact):** Audio capture, window/app capture mode, Unix socket IPC (status/stop work via PID today).

---

## How to continue

1. **Audio:** Add audio capture when `audio_enabled`, 3h segments, MP3; wire into export when enabled.
2. **Window/app capture:** Implement `capture_mode: window | app` in ScreenCaptureService (filter by window or app).
3. **Unix socket:** Optional; daemon could listen on tmrc.sock for status/stop; CLI already uses PID + SIGTERM.
4. Run and extend tests in `specs/test.md`; many unit tests added (Export, Ask, TimeRange, Segmenter, Index). E2E items (e.g. #14–15, #45–46, #55–56, #84) require manual or CI with capture.
