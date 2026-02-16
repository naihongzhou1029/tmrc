# Building progress: tmrc

This file tracks implementation progress against the plan derived from `spec.md` and `README.md`. Use it to resume work and to know what is done vs pending. Validate behaviour with the test matrix in `specs/test.md`.

**Last synced:** After initial implementation (CLI, daemon, capture pipeline, storage, index, ask, export stub, logging). Not all plan items were implemented.

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
| Permission revoked mid-session → toast, sync, quit | Pending | No toast; daemon does not detect revoke and exit |
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
| Disk full / low space → sync, toast, exit | Pending | ensureWritable at start; no runtime check or toast |
| Usage report | Done | tmrc status shows disk usage |
| Unix socket (tmrc.sock) | Pending | Path defined; not created or used for CLI–daemon IPC |

---

## 3. Indexing Pipeline

| Item | Status | Notes |
|------|--------|--------|
| Index per session (SQLite in index/) | Done | IndexSchema + IndexManager |
| Schema (id, time range, ocrText, sttText, filePath, status) | Done | Segments written with status "pending", ocrText/sttText nil |
| OCR (Vision VNRecognizeTextRequest, ocr_recognition_languages) | Pending | Config keys exist; no OCR pipeline on segments |
| OCR granularity (per_segment_summary etc.) | Pending | Config only |
| Speech-to-text | Pending | Not implemented |
| Embeddings (Advanced mode) | Pending | Spec 3.5 still open; not implemented |
| Index build failure → partial index, notify user | Pending | No OCR yet; no toast/notification path |
| Rebuild index from segments (subcommand/flag) | Pending | No rebuild command |
| Re-index idempotency | Pending | N/A until pipeline exists |

---

## 4. Recall: Ask

| Item | Status | Notes |
|------|--------|--------|
| Query scope (ask_default_range, --since, --until) | Done | TimeRangeParser + AskEngine |
| Keyword search (OCR/STT text) | Done | IndexManager.search (LIKE); OCR text empty until pipeline |
| Template answer, citations (YYYY-MM-DD HH:MM:SS, segment ref) | Done | AskEngine |
| No results / empty index messaging | Done | AskEngine |
| Multiple matches, ranking | Done | By time; limit 50 |

---

## 5. Recall: Export

| Item | Status | Notes |
|------|--------|--------|
| --from / --to (absolute and relative), -o | Done | ExportCommand parses; ExportEngine stub |
| --query (merged range) | Pending | Stub rejects; no query-to-range then stitch |
| Stitch multiple segments → one MP4/GIF | Pending | ExportEngine throws "not yet implemented" |
| Missing segment → fail with clear message | Pending | Stub fails on no segments; real export not implemented |
| Export format (MP4/GIF), quality levels | Pending | Stub only |
| Output overwrite, concurrent exports | Pending | Stub only |

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
| Crash recovery (new session, ignore partial segments) | Pending | No startup cleanup of partials; behaviour implicit |
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

- **Done:** CLI (record, ask, export, install, uninstall, status), config (YAML + defaults), daemon (start/stop, ScreenCaptureKit, event segmenter, segment writer), storage layout and retention, SQLite index and keyword search, time-range parsing, ask engine and citations, export stub (clear errors), logging (file, rotation, version, debug).
- **Pending (high impact):** OCR pipeline (Vision), export stitch/encode (real MP4/GIF from segments), permission-revoked detection and toast, optional: audio capture, window/app capture mode, rebuild-index subcommand, disk-full toast, Unix socket IPC.

---

## How to continue

1. **OCR pipeline:** After each segment is written (or in a separate pass), run Vision OCR on segment frames (or a keyframe), write `ocrText` to index, set `status` to `"indexed"`. See spec §3.2, §3.3.
2. **Export:** In `ExportEngine`, resolve segments for the time range (or query), decode segment MP4s, concatenate/re-encode to one file (AVFoundation or similar), support MP4 (H.264) and GIF. See spec §5.3, test.md #45–56.
3. **Permission revoked:** Use ScreenCaptureKit or system APIs to detect loss of screen capture permission; show macOS notification (UserNotifications), flush, exit. See spec §1.8, test.md #15.
4. Run and extend tests in `specs/test.md` as features are added; update this file when syncing progress.
