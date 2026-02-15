# Architecture Review: Implementation Questions & Suggestions

Senior review of the tmrc concept (README.md). Items are phrased as tasks or open questions to clarify before or during implementation. More clarity up front reduces rework.

Refer to items by section and number (e.g. "1.3" or "Recording Q3").

---

## 1. Recording & Capture

- [x] 1. Chunk/segment duration — **Event-based recording**, not fixed-duration segments. "Time" is the sample rate for parsing events. Default sample rate: **32.2 ms** (≈ 30 FPS). Configurable via `config.yaml` → `sample_rate_ms`. Segment/chunk boundaries are driven by events and this sample rate; exact storage layout TBD in Storage section.
- [x] 2. Segment boundaries — **Event-based segmentation.** Events (e.g. window show, cursor move) are sampled at the configured rate (default 32.2 ms). **Minimum recordable unit:** one event always yields **at least one 32.2 ms clip**; even with no further interactions we record that clip and flush when the next frame has no events. A segment is flushed/synced to DB when **there are no further events in the next frame**. Example: cursor moving over 1 s → ~31 events, then flush; single "window show" with no further changes → one 32.2 ms clip, then flush. "DB" used as placeholder until concrete storage is chosen.
- [x] 3. Frame rate and resolution — Default capture/parse rate is **32.2 ms** (30 FPS), configurable via `config.yaml` (`sample_rate_ms`). Resolution (full display, scaled, per-display) and impact on storage/OCR TBD.
- [x] 4. Multiple displays — Configurable in **config.yaml** (e.g. `display`). **Default: main display only.** Other options (combined, or per-display index) TBD. Representation in index and export follows the chosen display source.
- [x] 5. Window vs full-screen capture — **Configurable in config.yaml** (e.g. `capture_mode`). **Default: full_screen.** Window and app filtering are supported; filtering rules (which window/app) TBD in implementation. ScreenCaptureKit supports both modes.
- [x] 6. Audio — **Simpler model:** no segmentation for audio. **Default: off**; enable in **config.yaml** (`audio_enabled`). When enabled, audio always records (continuous). For export when audio is enabled: **time-based segments** — **3 hours** per segment; export as **MP3** with **timestamp as base name** of file. Sample rate and format for storage and STT TBD.
- [x] 7. Capture during lock/sleep — **Configurable in config.yaml** (e.g. `record_when_locked_or_sleeping`). **Default: false** — do not record during lock/sleep (pause or stop). User can enable if needed (rare use case). Document behaviour in both modes.
- [x] 8. Permissions — **Before recording:** app must request (and obtain) Screen Recording permission, and Microphone if audio is enabled; cannot proceed until granted. **If permission is revoked mid-session:** (1) post a **toast** (macOS notification) to the user, (2) **sync current artifacts to storage**, (3) **quit the app**. No retry or back-off while running; clean exit after flush.
- [x] 9. Recording identity — **Multiple sessions supported.** Default session name is **"default"** (configurable in config.yaml as `session`; overridable via CLI e.g. `tmrc record --session work`). Storage layout and CLI semantics are per-session. **Session ending:** a session ends when the recording process exits. **On process termination** (e.g. Ctrl+C, Activity Monitor quit, or permission revoked): **sync current artifacts to storage**, then exit. Ensures no data loss on graceful or forced quit.

---

## 2. Storage & Retention

- [x] 1. Storage root — **Default: `~/.tmrc/`.** Configurable (e.g. in config.yaml as `storage_root`). Overridable via env or config TBD. Document.
- [x] 2. Directory layout — **Index:** one **single index file per session**; each entry has its own timestamp. Index file **base name = session name** (e.g. session `default` → index `default.<ext>`, session `work` → `work.<ext>`). Concrete segment schema (e.g. `YYYY-MM-DD/segment_<id>.<ext>` vs flat) and exact index file extension/format TBD.
- [x] 3. Retention policy — **Session-based.** Both **max age** and **max disk usage** apply per session (no conflict; e.g. keep 7 days *and* cap at 50 GB). **Ring-buffer semantics:** when a new recording must be saved and the limit is reached (e.g. 8th day), **drop the oldest** (e.g. 1st day) and insert the new one; same idea for disk quota (evict oldest segments first). Defaults (e.g. 7 days, 50 GB) and config keys TBD; user can disable or tune.
- [x] 4. Disk full / low space — **Same abort principle:** when volume is full or below threshold, (1) **sync current artifacts to storage**, (2) **toast** a message to the user, (3) **exit the app**. No silent continue or drop-oldest-for-new. Threshold and exact user-facing message TBD.
- [x] 5. Quota per process — No hard cap. Provide an **option or subcommand** to **list usage report** to the user (e.g. per session, per day, total). User can monitor and act; avoids need for automatic quota enforcement.
- [x] 6. File formats — **Storage:** use the **most size-effective** format (e.g. MP4 with HEVC or similar; TBD). **Export:** support **H.264-compatible video** (for compatibility) and **GIF** when the user wants. Re-encode from stored format to H.264 or GIF on export as needed.
- [x] 7. Deduplication — **Addressed by event-based model:** we only record when events occur (and flush when next frame is quiet); static screen with no events produces no new segments. Explicit frame-level deduplication (e.g. within-segment) **out of scope for v1**.

---

## 3. Indexing Pipeline

**Indexing/recall mode (two presets):** **Advanced** = best UX: real-time indexing, full OCR, semantic (embeddings), LLM answers, proper multi-match handling, re-indexing; all sub-options configurable, defaults = best. **Normal** = lighter burden: no sub-options exposed; all defaults = lighter (e.g. lighter OCR, keyword-only, template answers, simpler match handling, no embeddings/LLM). Configurable in config (e.g. `index_mode: advanced | normal`). Real-time indexing is must-have for best UX (Advanced); Normal may use real-time with lighter pipeline or lighter schedule TBD.

- [x] 1. When to index — **Advanced:** real-time (index as segments are closed); must-have for best UX. **Normal:** lighter default (real-time with lighter pipeline, or batch; TBD). Trade-off: latency vs CPU/battery; mode choice captures this.
- [x] 2. OCR engine — **Backend: Vision `VNRecognizeTextRequest` only** (no pluggable backends). **Default languages** in config: `ocr_recognition_languages`: **["en-US", "zh-Hant", "zh-Hans"]**. User can add more locale strings (BCP 47 / Apple locale IDs) in config; comments in config explain how. No auto-detect; languages must be set. **Advanced:** full quality, configurable; **Normal:** lighter default. Fallback when OCR fails or returns empty TBD.
- [x] 3. OCR granularity — **Default for both modes: per-segment summary** (one OCR result per segment; balanced). **Advanced:** user can configure other granularities (e.g. per-frame, keyframes). **Normal:** no sub-options; always per-segment summary. Maps to "search by time" and "search by query."
- [x] 4. Speech-to-text — **Apple Speech Framework** (no external STT). Speech/audio is not a primary focus; language, model, offline/online, and alignment of audio to segments (timestamps) TBD in implementation.
- [ ] 5. Embeddings — **Advanced:** in scope; model, scope, storage configurable; default = best for semantic "ask". **Normal:** not used (keyword-only). Storage format and index type TBD.
- [x] 6. Index storage format — **Single SQLite per session** (base name = session name, e.g. `default.sqlite`). Schema: segment id, time range, OCR text, STT text, optional embedding refs. Version schema for future migrations TBD.
- [x] 7. Index build failure — **Partial index allowed.** When OCR/STT fails for a segment, **notify the user** (e.g. toast or status) so they know there was a failure and can review the generated video themselves. "Ask"/export may have no or stale data for that segment; user can still watch the recording. Retry policy (e.g. retry once then mark failed) TBD.
- [x] 8. Index corruption / recovery — **Recovery = regenerate from source of truth (segment files).** Option A: on detection of corruption, **rebuild index from segments** (re-run pipeline, write new SQLite). Also provide a **user-facing option** to manually **rebuild the index from source of truth** (e.g. subcommand or flag); same pipeline as recovery. Applies to both modes.
- [x] 9. Re-indexing — **Advanced:** supported (re-run indexer on existing segments; idempotency/overwrite configurable). **Normal:** not exposed or lighter default. Improves UX without re-recording.

---

## 4. Recall: "Ask" (Natural Language → Text)

Mode (Advanced vs Normal) applies: Advanced = full retrieval + LLM + multi-match handling; Normal = keyword-only, template, lighter defaults.

- [x] 1. Query scope — **Default: last 24h**, configurable in **config.yaml** (e.g. `ask_default_range: 24h`). CLI flags **`--since`** and **`--until`** let the user override the range per invocation.
- [x] 2. Retrieval path — **Advanced:** semantic (embeddings) or hybrid with keyword; configurable; default = best. **Normal:** keyword-only (OCR/STT text). Mode choice in config.
- [x] 3. Answer generation — **Advanced:** LLM (local or API); configurable; default = best. **Normal:** template (e.g. "Segment X at 14:32: …"). Model, context window, segment passing TBD for Advanced.
- [x] 4. Citation / time references — Every answer includes **timestamps** (and/or segment IDs) for follow-up export. **Format: date-time, 24h** (e.g. `2025-02-15 14:32:00`). Use for `--from` / `--until` in export. Applies to both modes. Timezone (e.g. local) TBD if not already specified elsewhere.
- [x] 5. No results — **Tell the user the truth** (no matches in the given scope). User decides what to do next (e.g. broaden time range, rephrase); no prescribed suggestions required. Applies to both modes.
- [x] 6. Multiple matches — **Advanced:** configurable; rank by relevance/time, upper bound; default = best UX. **Normal:** lighter default (e.g. fewer segments, simpler ranking). Avoid huge replies.
- [x] 7. Privacy — **No exclusion options** (no per-app or per–time-range filtering for "ask" or indexing). Enumerating what not to record is impractical. If the user knows it's not a proper moment to record, they **quit the app** themselves. User responsibility.

---

## 5. Recall: Export (Time Range or Query → MP4/GIF)

- [x] 1. Time range semantics — `--from` / `--to`: **both absolute and relative** (e.g. "1h ago"). **Timezone: local time** (user-facing). Boundaries inclusive and sub-segment precision (e.g. request 14:32:00–14:32:30 with variable-length segments) TBD.
- [x] 2. Query-to-export — When export is driven by a query: **one merged range** — take earliest start and latest end across all matches, export one clip spanning that range (includes gaps between matches). CLI surface: e.g. `tmrc export --query "..."`.
- [x] 3. Stitching — Export may span multiple segments: **decode** available segments, **concat** (or re-encode) in order. **Gaps:** stitch **all available** segments only; **skip** missing or corrupted segments (do not preserve or include them; output may have time jumps over gaps). No placeholder for missing segments.
- [x] 4. Export codec and quality — **Default quality: high.** Three levels for advanced users: **low** (720p, ~2 Mbps), **medium** (1080p, ~5 Mbps), **high** (source resolution or 1080p+, ~8 Mbps). MP4: H.264 for compatibility. GIF: same level drives resolution/frame rate; palette TBD. Config: `export_quality: high`. **Audio export:** when `audio_enabled`, 3-hour segments, MP3, timestamp as base name.
- [x] 5. GIF limits — **GIF is a CLI export option only** (e.g. `--format gif`), not in config.yaml. User explicitly requests GIF when exporting; we assume they know the trade-off (large, slow). No configurable limits or "suggest MP4" in config. Implementation may enforce a reasonable max duration/size to avoid runaway exports; TBD.
- [x] 6. Output path — **`-o`** (or **`--output-path`**): path for export file. **If file exists: overwrite by default, no warning.** Default output path when `-o` is omitted TBD (e.g. cwd or session/date-based).
- [x] 7. Concurrent exports — **No limitations;** allow multiple `tmrc export` in parallel. System resource allocation is the natural limit; no daemon queue or serialization.
- [x] 8. Export while recording — **Allowed.** Implementation must ensure segment files are not read while being written (e.g. only export from closed/flushed segments, or safe read semantics so in-progress segments are excluded or copied safely).

---

## 6. CLI & Daemon

- [ ] 1. Daemon process model — Single process (LaunchAgent) or CLI spawns a child daemon. How the daemon is started (e.g. `launchctl` vs `tmrc record` starts it). Lifecycle: start on login vs on first `tmrc record`.
- [ ] 2. Daemon discovery — How CLI finds the daemon: Unix socket path, PID file, or XPC. Same machine only; no remote.
- [ ] 3. tmrc record semantics — Exact meaning: "start recording," "stop recording," "ensure daemon is running," "show status," or combination (e.g. `tmrc record` toggles, `tmrc record --start`/`--stop`). Subcommands or flags to avoid ambiguity.
- [x] 4. Configuration — Config file: **`config.yaml`** in the **project root** (for this repo). First option: **`sample_rate_ms`** (default 32.2, ≈ 30 FPS), with comments in file. For installed CLI (e.g. Homebrew), config location may be overridable or default to e.g. `~/.config/tmrc/config.yaml`; TBD. Which options are config-only vs overridable by CLI TBD (e.g. retention, paths, OCR language).
- [ ] 5. Logging — Where daemon and CLI log (stderr, file, os_log). Log level and rotation for daemon.
- [ ] 6. Single instance — Only one recorder per machine (or per user). How to enforce and what error to show if a second instance is attempted.
- [ ] 7. Upgrade while recording — Policy when binary is replaced (e.g. via Homebrew): daemon keeps running on old binary until restart, or restart on upgrade. Document and optionally add "version" handshake between CLI and daemon.

---

## 7. Security & Privacy

- [ ] 1. Data at rest — Whether recordings or index are encrypted (e.g. FileVault only vs per-file encryption). If not in scope for v1, state explicitly.
- [ ] 2. Access control — Only the owning user can read recordings/index (rely on filesystem permissions). Any multi-user or "admin can read" requirement?
- [ ] 3. Secrets in capture — No automatic redaction. Document that users should be aware sensitive data may be in recordings; optional future: exclude region or app.
- [ ] 4. Audit — Whether to log "who ran ask/export and when" for sensitive environments. If not in scope, state as non-goal.

---

## 8. Operations & Lifecycle

- [ ] 1. Installation — How the daemon is installed (e.g. `tmrc install` that places LaunchAgent plist and creates dirs). Uninstall / disable recording cleanly.
- [ ] 2. Health check — Way to verify daemon is running and capturing (e.g. `tmrc status` showing last segment time and disk usage).
- [ ] 3. Graceful shutdown — On SIGTERM or SIGINT (e.g. Ctrl+C, Activity Monitor quit), daemon **syncs current artifacts to storage**, then exits. Document and test.
- [ ] 4. Crash recovery — If daemon crashes, next start: resume from last segment or new session. How partial segments are handled (discard or keep as "incomplete").
- [ ] 5. Clock changes — Behaviour when system time is adjusted (e.g. NTP or manual): segment timestamps and export time ranges. Prefer monotonic or wall-clock for segment naming.
- [ ] 6. Timezone / DST — Store and display times in local timezone; document DST transition handling (e.g. ambiguous "2:30" when clock falls back).

---

## 9. Edge Conditions & Failure Modes

- [ ] 1. Very long sessions — Single continuous recording for days: segment count and index size; any practical limit or warning (e.g. "recording for 7 days").
- [ ] 2. Permission revoked mid-session — User revokes Screen Recording: daemon gets failure from ScreenCaptureKit. Stop recording, clear error in status, and optionally notify (e.g. os_log or status message). Do not silently continue with blank frames.
- [ ] 3. Read-only or external volume — If storage root is on a read-only or disconnected volume: fail fast at daemon start or at first write, with clear error.
- [ ] 4. Export of missing segment — Requested time range references a deleted or missing segment: fail with clear message and optionally suggest nearest available range.
- [ ] 5. Ask with empty index — No segments indexed yet (e.g. fresh install): friendly message and suggest waiting or checking `tmrc status`.
- [ ] 6. Duplicate or overlapping segments — If clock skew or bug produces overlapping segment times: policy for export and search (e.g. prefer newer, or merge).
- [ ] 7. Resource exhaustion — CPU/memory spike during indexing or export. Consider throttling, queue length limits, or user-configurable concurrency.
- [ ] 8. Binary rename or copy — If user runs `tmrc` from a copy with different path: daemon discovery and config path should still be deterministic (e.g. by install location or fixed paths, not "current binary path" for config).

---

## 10. Observability & Debugging

- [ ] 1. Metrics — Optional counters: segments written, index lag, export count. Where they are exposed (e.g. file, or future Prometheus) and whether they are in scope for v1.
- [ ] 2. Debug mode — `tmrc --debug` or `TMRC_DEBUG=1`: verbose logs, preserve temporary files, or dry-run for export. Document for support.
- [ ] 3. Reproducibility — Version string in CLI and daemon (`tmrc --version`); same version in logs to help diagnose issues.

---

## Progress (where we left off)

- **Sections 1–5 resolved** (Recording, Storage, Indexing, Ask, Export). **config.yaml** updated with: sample_rate_ms, display, capture_mode, audio_enabled, record_when_locked_or_sleeping, session, storage_root, index_mode, ocr_*, ask_default_range, export_quality.
- **Next to discuss:** Section 6 CLI & Daemon — Q1 (Daemon process model), then 6.2–6.7, then Sections 7–10.

---

## Summary

- 1. Recording (1–9): Chunk size, resolution, FPS, multi-display, audio sync, lock/sleep, permissions, session identity.
- 2. Storage (1–7): Layout, retention, disk full, format, optional dedup.
- 3. Indexing (1–9): When, OCR/STT/embeddings choices, schema, failure and recovery, re-index.
- 4. Ask (1–7): Scope, retrieval (keyword/semantic), answer generation, citations, no/many results.
- 5. Export (1–8): Time semantics, query-to-range, stitching, codec, GIF limits, concurrency.
- 6. CLI/Daemon (1–7): Process model, discovery, `record` semantics, config, single instance, upgrade.
- 7. Security (1–4): At-rest, access, secrets, audit.
- 8. Ops (1–6): Install, health, shutdown, crash recovery, clock/DST.
- 9. Edge cases (1–8): Long sessions, permission revoked, missing segments, empty index, resource limits.
- 10. Observability (1–3): Metrics, debug, versioning.

Resolve or document each item before or during implementation to avoid late rework and inconsistent behaviour.
