# Architecture Review: Implementation Questions & Suggestions

Senior review of the tmrc concept (README.md). Items are phrased as tasks or open questions to clarify before or during implementation. More clarity up front reduces rework.

Refer to items by section and number (e.g. "1.3" or "Recording Q3").

---

## 1. Recording & Capture

- [ ] 1. Chunk/segment duration — Decide fixed duration for "time-chunked" segments (e.g. 30s, 1m, 5m). Trade-off: shorter = finer recall granularity and more segment metadata; longer = fewer files and possibly simpler indexing. Document the choice and rationale.
- [ ] 2. Segment boundaries — Are segment boundaries strict (e.g. every 60s wall-clock) or best-effort (e.g. keyframe-aligned)? Affects how `--from`/`--to` map to files and export stitching.
- [ ] 3. Frame rate and resolution — Target FPS (e.g. 1, 5, 15, 30) and resolution (full display, scaled, per-display). Define defaults and whether they are user-configurable; impact on storage and OCR quality.
- [ ] 4. Multiple displays — Behaviour with multiple monitors: single combined capture, primary only, or user choice (e.g. `--display 0`). How this is represented in the index and in export.
- [ ] 5. Window vs full-screen capture — ScreenCaptureKit supports both. Decide default (likely full screen for "rewind-like") and whether to support window/app filtering for privacy or focus.
- [ ] 6. Audio — Sync strategy (e.g. same segment boundary as video, or separate audio chunks with timestamps). Sample rate and format for storage and for STT.
- [ ] 7. Capture during lock/sleep — Policy when display is locked or machine is sleeping: pause recording, stop, or keep last frame (and document behaviour).
- [ ] 8. Permissions — Screen Recording (and Microphone if audio) are required. Define: how to detect missing permissions, what error messages to show, and whether the daemon backs off or retries when permission is revoked mid-session.
- [ ] 9. Recording identity — Is there a single "current session" or multiple named sessions (e.g. `tmrc record --session work`)? Affects storage layout and CLI semantics.

---

## 2. Storage & Retention

- [ ] 1. Storage root — Default directory for recordings and index (e.g. `~/Library/Application Support/tmrc/` or configurable). Document and make overridable (env or config).
- [ ] 2. Directory layout — Concrete schema: e.g. `YYYY-MM-DD/segment_<id>.<ext>` vs flat with prefixed IDs. Include where sidecar index (and any SQLite/DB) lives.
- [ ] 3. Retention policy — Max age or max disk usage for auto-deletion. Defaults (e.g. "keep 7 days" or "keep until 50 GB") and whether user can disable or tune.
- [ ] 4. Disk full / low space — Behaviour when volume is full or below a threshold: stop recording, drop oldest segments, or fail with clear error. Define threshold and user-facing message.
- [ ] 5. Quota per process — Any cap on total size per "session" or per day to avoid runaway growth (e.g. bug or misconfiguration).
- [ ] 6. File formats — Container/codec for stored segments (e.g. MP4 with H.264/HEVC). Same as export codec or different (e.g. internal proxy vs export encode)? Impacts re-encode cost for export.
- [ ] 7. Deduplication — Whether identical or near-identical frames are deduplicated (e.g. static screen for hours). If yes, define strategy and how it interacts with time-based recall.

---

## 3. Indexing Pipeline

- [ ] 1. When to index — Real-time (as segments are closed) vs batch (periodic job). Trade-off: latency for "ask" vs CPU/battery and implementation complexity.
- [ ] 2. OCR engine — Use Vision (VNRecognizeTextRequest) only or allow pluggable backends. Language(s) supported and fallback when OCR fails or returns empty.
- [ ] 3. OCR granularity — Per-frame, per-segment summary, or keyframes only. How this maps to "search by time" and "search by query."
- [ ] 4. Speech-to-text — Engine choice (e.g. Apple Speech Framework, or external). Language and model; offline vs online requirement. How audio segments are aligned to segments (timestamps).
- [ ] 5. Embeddings — If "optional embeddings" are in scope: which model (e.g. small local vs API), scope (per segment, per sentence, per window). Storage format and index type (e.g. vector DB or in-file sidecar).
- [ ] 6. Index storage format — Single SQLite, per-segment JSON, or hybrid. Schema: segment id, time range, OCR text, STT text, optional embedding refs. Version schema for future migrations.
- [ ] 7. Index build failure — Retry policy for failed OCR/STT (e.g. transient error). Whether partial index is allowed and how "ask"/export behave when index is missing or stale for a segment.
- [ ] 8. Index corruption / recovery — How to detect and recover (e.g. rebuild from segments, or mark segment as unindexed and re-run pipeline).
- [ ] 9. Re-indexing — Support for re-running indexer on existing segments (e.g. after adding embeddings or fixing a bug). Idempotency and overwrite semantics.

---

## 4. Recall: "Ask" (Natural Language → Text)

- [ ] 1. Query scope — Default time range for "ask" (e.g. last 24h, last 7 days, or all). Configurable and/or flags like `--since`, `--until`.
- [ ] 2. Retrieval path — Keyword search only (OCR/STT text) vs semantic (embeddings) vs hybrid. Decision affects dependency on embedding model and latency.
- [ ] 3. Answer generation — How the text reply is produced: template (e.g. "Segment X at 14:32: …"), LLM (local or API), or rule-based summarization. If LLM: model, context window, and how to pass retrieved segments.
- [ ] 4. Citation / time references — Whether every answer includes timestamps or segment IDs for follow-up export; format (e.g. `--from 14:32:00 --to 14:33:15`).
- [ ] 5. No results — Behaviour when query matches nothing: message wording and whether to suggest broadening time range or query.
- [ ] 6. Multiple matches — How many segments to return and how to rank (relevance, time). Upper bound to avoid huge replies.
- [ ] 7. Privacy — Whether "ask" can be restricted to exclude certain apps or time ranges (e.g. no indexing of password manager window). If so, model in index and retrieval.

---

## 5. Recall: Export (Time Range or Query → MP4/GIF)

- [ ] 1. Time range semantics — `--from` / `--to`: format (absolute time vs relative like "1h ago"), timezone (local vs UTC), and whether boundaries are inclusive. How sub-segment precision is handled (e.g. request 14:32:00–14:32:30 with 60s segments).
- [ ] 2. Query-to-export — When export is driven by a query (e.g. "export when I was in Slack"), rule for deriving time range: single best match, N matches (multiple clips), or merged range. CLI surface (e.g. `tmrc export --query "..."`).
- [ ] 3. Stitching — Export may span multiple segments. Define: decode segments, concat (or re-encode), and handle gaps (e.g. missing segment → skip or insert placeholder).
- [ ] 4. Export codec and quality — MP4: codec (H.264/HEVC), resolution, bitrate. GIF: palette, resolution, frame rate (often lower). Defaults and flags (e.g. `--quality high`).
- [ ] 5. GIF limits — GIF is often large and slow. Max duration or size for GIF export; suggest MP4 for long clips if applicable.
- [ ] 6. Output path — `-o` behaviour: overwrite, uniquify (e.g. append timestamp), or fail if exists. Default output path when `-o` is omitted.
- [ ] 7. Concurrent exports — Allow multiple `tmrc export` in parallel or serialize (e.g. daemon queue). Resource (CPU/memory) consideration.
- [ ] 8. Export while recording — Allowed or not; if allowed, ensure segment files are not truncated while being read.

---

## 6. CLI & Daemon

- [ ] 1. Daemon process model — Single process (LaunchAgent) or CLI spawns a child daemon. How the daemon is started (e.g. `launchctl` vs `tmrc record` starts it). Lifecycle: start on login vs on first `tmrc record`.
- [ ] 2. Daemon discovery — How CLI finds the daemon: Unix socket path, PID file, or XPC. Same machine only; no remote.
- [ ] 3. tmrc record semantics — Exact meaning: "start recording," "stop recording," "ensure daemon is running," "show status," or combination (e.g. `tmrc record` toggles, `tmrc record --start`/`--stop`). Subcommands or flags to avoid ambiguity.
- [ ] 4. Configuration — Config file location (e.g. `~/.config/tmrc/config.yaml`) and format. Which options are config-only vs overridable by CLI (e.g. retention, paths, OCR language).
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
- [ ] 3. Graceful shutdown — On SIGTERM, daemon flushes and closes current segment, then exits. Document and test.
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
