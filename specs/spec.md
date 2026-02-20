# Architecture Review: Implementation Questions & Suggestions

Senior review of the tmrc concept (README.md). Items are phrased as tasks or open questions to clarify before or during implementation. More clarity up front reduces rework.

Refer to items by section and number (e.g. "1.3" or "Recording Q3").

---

## 1. Recording & Capture

- [x] 1. Chunk/segment duration — **Event-based recording**, not fixed-duration segments. "Time" is the sample rate for parsing events. Default sample rate: **100 ms** (10 FPS). Configurable via `config.yaml` → `sample_rate_ms`. Segment/chunk boundaries are driven by events and this sample rate; exact storage layout TBD in Storage section.
- [x] 2. Segment boundaries — **Event-based segmentation.** Events (e.g. window show, cursor move) are sampled at the configured rate (default 100 ms). **Minimum recordable unit:** one event always yields **at least one sample-interval clip**; even with no further interactions we record that clip and flush when the next frame has no events. A segment is flushed/synced to DB when **there are no further events in the next frame**. Example: cursor moving over 1 s at 10 FPS → ~10 events, then flush; single "window show" with no further changes → one 100 ms clip, then flush. "DB" used as placeholder until concrete storage is chosen.
- [x] 3. Frame rate and resolution — Default capture/parse rate is **100 ms** (10 FPS), configurable via `config.yaml` (`sample_rate_ms`). Resolution (full display, scaled, per-display) and impact on storage/OCR TBD.
- [x] 4. Multiple displays — Configurable in **config.yaml** (e.g. `display`). **Default: main display only.** Other options (combined, or per-display index) TBD. Representation in index and export follows the chosen display source.
- [x] 5. Window vs full-screen capture — **Configurable in config.yaml** (e.g. `capture_mode`). **Default: full_screen.** Window and app filtering are supported; filtering rules (which window/app) TBD in implementation. ScreenCaptureKit supports both modes.
- [x] 6. Audio — **Simpler model:** no segmentation for audio. **Default: off**; enable in **config.yaml** (`audio_enabled`). When enabled, audio always records (continuous). For export when audio is enabled: **time-based segments** — **3 hours** per segment; export as **MP3** with **timestamp as base name** of file. Sample rate and format for storage and STT TBD.
- [x] 7. Capture during lock/sleep — **Configurable in config.yaml** (e.g. `record_when_locked_or_sleeping`). **Default: false** — do not record during lock/sleep (pause or stop). User can enable if needed (rare use case). Document behaviour in both modes.
- [x] 8. Permissions — **Before recording:** app must request (and obtain) Screen Recording permission, and Microphone if audio is enabled; cannot proceed until granted. **If permission is revoked mid-session:** (1) post a **toast** (macOS notification) to the user, (2) **sync current artifacts to storage**, (3) **quit the app**. No retry or back-off while running; clean exit after flush.
- [x] 9. Recording identity — **Multiple sessions supported.** Default session name is **"default"** (configurable in config.yaml as `session`; overridable via CLI e.g. `tmrc record --session work`). Storage layout and CLI semantics are per-session. **Session ending:** a session ends when the recording process exits. **On process termination** (e.g. Ctrl+C, Activity Monitor quit, or permission revoked): **sync current artifacts to storage**, then exit. Ensures no data loss on graceful or forced quit.

---

## 2. Storage & Retention

- [x] 1. Storage root — **Default: `~/.tmrc/`.** Configurable (e.g. in config.yaml as `storage_root`). Overridable via env or config TBD. Document.
- [x] 2. Directory layout — **Index:** one **single index file per session** under **`index/`** folder; path `index/<session>.<ext>` (e.g. session `default` → `index/default.sqlite`, session `work` → `index/work.sqlite`). Concrete segment schema (e.g. `segments/YYYY-MM-DD/segment_<id>.<ext>` vs flat) TBD.
- [x] 3. Retention policy — **Session-based.** Both **max age** and **max disk usage** apply per session (no conflict; e.g. keep 30 days *and* cap at 50 GB). **Ring-buffer semantics:** when a new recording must be saved and the limit is reached (e.g. 31st day), **drop the oldest** (e.g. 1st day) and insert the new one; same idea for disk quota (evict oldest segments first). **Defaults: `retention_max_age_days: 30`, `retention_max_disk_bytes: 53687091200` (50 GB).** Set either to `0` to disable that dimension. Config keys: `retention_max_age_days` (int, days) and `retention_max_disk_bytes` (long, bytes) in `config.yaml`.
- [x] 4. Disk full / low space — **Same abort principle:** when volume is full or below threshold, (1) **sync current artifacts to storage**, (2) **toast** a message to the user, (3) **exit the app**. No silent continue or drop-oldest-for-new. Threshold and exact user-facing message TBD.
- [x] 5. Quota per process — No hard cap. Provide an **option or subcommand** to **list usage report** to the user (e.g. per session, per day, total). User can monitor and act; avoids need for automatic quota enforcement.
- [x] 6. File formats — **Storage:** use the **most size-effective** format (e.g. MP4 with HEVC or similar; TBD). **Export:** support **H.264-compatible video** (for compatibility) and **GIF** when the user wants. Re-encode from stored format to H.264 or GIF on export as needed.
- [x] 7. Deduplication — **Addressed by event-based model:** we only record when events occur (and flush when next frame is quiet); static screen with no events produces no new segments. Explicit frame-level deduplication (e.g. within-segment) **out of scope for v1**.

### Folder structure (under `storage_root`, default `~/.tmrc/`)

All paths are relative to `storage_root` (configurable; default `~/.tmrc/`). Deterministic: do not depend on binary path (Section 9.8).

| Path | Purpose |
|------|--------|
| `tmrc.pid` | Daemon PID file (CLI discovers daemon via this). |
| `tmrc.sock` | Unix socket for CLI–daemon communication (exact name TBD). |
| `tmrc.log` | Single log file in root; daemon and CLI both write here. **Single-file rotation** (time-based, 7 days): rotate in place or overwrite; no `log/` subfolder. |
| `index/<session>.sqlite` | Index per session in **`index/`** folder (e.g. `index/default.sqlite`, `index/work.sqlite`). |
| **Segments** | Concrete schema TBD: e.g. `segments/YYYY-MM-DD/segment_<id>.<ext>` or flat `segments/<id>.<ext>`. |
| **Audio** (if enabled) | 3-hour segments, MP3, timestamp as base name; subdir or location TBD. |

**Config (outside `storage_root`):**

- **Development (repo):** `config.yaml` in **project root**.
- **Installed CLI (e.g. Homebrew):** default `~/.config/tmrc/config.yaml` (TBD); overridable via env.

**Example (default session, `storage_root` = `~/.tmrc/`):**

```
~/.tmrc/
├── tmrc.pid
├── tmrc.sock
├── tmrc.log           # single file, 7-day rotation in place
├── index/
│   └── default.sqlite
└── segments/          # schema TBD
    └── ...
```

---

## 3. Indexing Pipeline

**Indexing/recall mode (two presets):** **Advanced** = best UX: real-time indexing, full OCR, semantic (embeddings), LLM answers, proper multi-match handling, re-indexing; all sub-options configurable, defaults = best. **Normal** = lighter burden: no sub-options exposed; all defaults = lighter (e.g. lighter OCR, keyword-only, template answers, simpler match handling, no embeddings/LLM). Configurable in config (e.g. `index_mode: advanced | normal`). Real-time indexing is must-have for best UX (Advanced); Normal may use real-time with lighter pipeline or lighter schedule TBD.

- [x] 1. When to index — **Advanced:** real-time (index as segments are closed); must-have for best UX. **Normal:** lighter default (real-time with lighter pipeline, or batch; TBD). Trade-off: latency vs CPU/battery; mode choice captures this.
- [x] 2. OCR engine — **Backend: Vision `VNRecognizeTextRequest` only** (no pluggable backends). **Default languages** in config: `ocr_recognition_languages`: **["en-US", "zh-Hant", "zh-Hans"]**. User can add more locale strings (BCP 47 / Apple locale IDs) in config; comments in config explain how. No auto-detect; languages must be set. **Advanced:** full quality, configurable; **Normal:** lighter default. Fallback when OCR fails or returns empty TBD.
- [x] 3. OCR granularity — **Default for both modes: per-segment summary** (one OCR result per segment; balanced). **Advanced:** user can configure other granularities (e.g. per-frame, keyframes). **Normal:** no sub-options; always per-segment summary. Maps to "search by time" and "search by query."
- [x] 4. Speech-to-text — **Apple Speech Framework** (no external STT). Speech/audio is not a primary focus; language, model, offline/online, and alignment of audio to segments (timestamps) TBD in implementation.
- [ ] 5. Embeddings — **Advanced:** in scope; model, scope, storage configurable; default = best for semantic "ask". **Normal:** not used (keyword-only). Storage format and index type TBD.
- [x] 6. Index storage format — **Single SQLite per session** in **`index/`** folder (e.g. `index/default.sqlite`, `index/work.sqlite`). Schema: segment id, time range, OCR text, STT text, optional embedding refs. Version schema for future migrations TBD.
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

- [x] 1. Daemon process model — **Two processes:** CLI and a separate child daemon. The daemon is **started by `tmrc record`** (not on login). When the user runs `tmrc record` and the daemon is already running, the CLI **tells the user that recording is in progress** (no second daemon). Lifecycle: first `tmrc record` spawns the daemon; daemon runs until stopped (e.g. `tmrc record --stop`) or process termination.
- [x] 2. Daemon discovery — **PID file** (e.g. `~/.tmrc/tmrc.pid` or under `storage_root`). CLI reads the PID and checks that the process exists; portable across Unix-like systems (macOS, Linux, BSD). For CLI–daemon communication (status, stop, etc.), use a **Unix socket** at a known path (e.g. under `~/.tmrc/`); also compatible on Unix-like systems. Same machine only; no remote. Exact paths TBD (e.g. configurable via `storage_root`).
- [x] 3. tmrc record semantics — **Subcommands/flags:** `tmrc record` or `tmrc record --start`: start recording (spawn daemon if needed; if daemon already running, report "already recording"). `tmrc record --stop`: stop recording (stop daemon, sync artifacts, exit). **Status:** "am I recording?" via `tmrc record --status` (or as part of `tmrc status` per Section 8.2). No toggle; explicit `--start`/`--stop` to avoid ambiguity.
- [x] 4. Configuration — Config file: **`config.yaml`** in the **project root** (for this repo). First option: **`sample_rate_ms`** (default 100, 10 FPS), with comments in file. For installed CLI (e.g. Homebrew), config location may be overridable or default to e.g. `~/.config/tmrc/config.yaml`; TBD. Which options are config-only vs overridable by CLI TBD (e.g. retention, paths, OCR language).
- [x] 5. Logging — **Log file only** (no stderr-only or os_log). Path: **`storage_root/tmrc.log`** (single file in root; no `log/` subfolder). Daemon and CLI both write to the same log file. **Level:** default **info**; configurable in config (e.g. `log_level: info`) if needed. **Rotation:** single-file, time-based; retain **7 days**, rotate in place or overwrite. Implementation details TBD.
- [x] 6. Single instance — **Daemon only:** exactly one recorder daemon per user (enforced via PID file under user's `storage_root`). When `tmrc record --start` is run and a daemon is already running, CLI reports that recording is already in progress and does not start a second daemon. **Ask and export:** multiple instances allowed—user may run several `tmrc ask` or `tmrc export` invocations concurrently (read-only; no conflict with single daemon). Error message when second daemon is attempted: e.g. "Recording is already in progress" or "Another tmrc recorder is already running"; exact wording TBD.
- [x] 7. Upgrade while recording — **Policy:** when the binary is replaced (e.g. via Homebrew), the daemon **keeps running on the old binary** until the user restarts it (e.g. `tmrc record --stop` then `tmrc record --start`, or process exit). No automatic restart on upgrade. **No version handshake** between CLI and daemon; document this behaviour so users know they may need to restart the daemon after upgrading to use new behaviour.

---

## 7. Security & Privacy

- [x] 1. Data at rest — **Encryption is an optional feature**, configurable in **config.yaml**, **disabled by default**. When enabled, encrypt segments with a key derived from the user's password. Key derivation, key storage (e.g. keychain), and UX for password entry are **to-do**; full design and implementation are optional for later. If disabled (default), rely on OS/FileVault only; no per-file encryption.
- [x] 2. Access control — **Typical case:** only the owning user can read recordings and index. **Rely on filesystem permissions** (e.g. `storage_root` under user's home with appropriate umask/permissions). No multi-user or "admin can read" requirement; document that tmrc does not add extra access control beyond the OS.
- [x] 3. Secrets in capture — **No automatic redaction** in v1. Document that users should be aware sensitive data may be in recordings and are responsible for when to record (e.g. stop recording before entering passwords). **Optional future:** exclude region or app; out of scope for v1.
- [x] 4. Audit — **Out of scope for v1.** No audit logging of "who ran ask/export and when." State as **non-goal**; users who need audit trails rely on OS or other tools.

---

## 8. Operations & Lifecycle

- [x] 1. Installation — **`tmrc install`:** create required dirs (e.g. `storage_root`, default `~/.tmrc/`), create default config if missing (e.g. copy or generate `config.yaml` in configured location). No LaunchAgent (daemon starts on first `tmrc record`). **`tmrc uninstall`:** stop the daemon cleanly (sync artifacts, exit), then optionally remove dirs/config per user choice (e.g. flag like `--remove-data` or leave data in place by default). Exact uninstall behaviour (prompt, flags) TBD. Improves UX for setup and teardown.
- [x] 2. Health check — **Dedicated command `tmrc status`:** verify daemon is running and capturing. Shows: daemon running yes/no (answers "am I recording?"), last segment time, disk usage (e.g. per session or total under `storage_root`), **retention config (`retention_max_age_days` and `retention_max_disk_bytes`)**. Optional: session name, config summary. Exact output format TBD. Canonical way to check recording and health; `tmrc record --status` (Section 6.3) may be a short alias or omitted in favour of `tmrc status`.
- [x] 3. Graceful shutdown — **Confirmed:** on SIGTERM or SIGINT (e.g. Ctrl+C, Activity Monitor quit), daemon **syncs current artifacts to storage**, then exits. Aligned with Recording 1.8/1.9. **Document** this behaviour and **test** it so shutdown is reliable.
- [x] 4. Crash recovery — **New session on next start.** No resume logic; when the daemon starts after a crash, it starts a **new session** (same session name if configured, but no continuation of the previous run). **Partial segments** left on disk from the crashed run: **discard or ignore** (do not use for export/index); implementation may delete incomplete files on startup or leave them unused. No post-crash resume processing.
- [x] 5. Clock changes — **Monotonic time** for segment boundaries (ordering stable when system clock is adjusted). **Wall-clock** for display and export (user-facing "when did this happen"). Store both as needed: monotonic for ordering/stitching, wall-clock for timestamps in index and CLI output. Document behaviour when NTP or manual clock change occurs.
- [x] 6. Timezone / DST — **Store and display in local time** (consistent with Ask 4, Export 1). **DST not in scope:** no special consideration for DST transitions or ambiguous times (e.g. "2:30" when clock falls back). Use system local time as-is; document if needed that v1 does not handle DST edge cases.

---

## 9. Edge Conditions & Failure Modes

- [x] 1. Very long sessions — **No limit and no warning.** Rely on retention policy (Section 2.3) and disk space; very long sessions are allowed. No practical cap or "recording for X days" warning.
- [x] 2. Permission revoked mid-session — **Same as Recording 1.8:** when permission is revoked, (1) **toast** the user, (2) **sync** current artifacts to storage, (3) **quit** the app. Do not silently continue with blank frames.
- [x] 3. Read-only or external volume — **Fail fast:** if `storage_root` is on a read-only or disconnected volume, detect at daemon start or at first write and **fail with a clear error** (no retry or silent continue). Optionally toast the user. Exact check point (start vs first write) TBD.
- [x] 4. Export of missing segment — When the requested time range references a **deleted or missing segment**, **fail the export** with a **clear message** (do not produce partial output with gaps). Optionally suggest the nearest available range. Align with or refine Export 5.3 as needed (explicit fail vs skip-missing semantics).
- [x] 5. Ask with empty index — When no segments are indexed yet (e.g. fresh install): show a **friendly message** and **optionally suggest waiting** (or checking `tmrc status`). Aligned with Ask 4.5 (no results → tell the truth).
- [x] 6. Duplicate or overlapping segments — **Prefer newer:** when segment times overlap or duplicate (e.g. clock skew or bug), use the **newer** segment for export and search; ignore the older. Consistent policy for stitching and ask.
- [x] 7. Resource exhaustion — **No extra limits for v1.** Rely on OS and hardware; user accepts load from heavy indexing or multiple exports. Throttling, queue limits, or configurable concurrency may be considered later.
- [x] 8. Binary rename or copy — **Deterministic paths:** daemon discovery (PID file, Unix socket) and config path must not depend on the current binary path. Use **fixed or deterministic locations** (e.g. `$HOME`, `storage_root` default `~/.tmrc/`, config from env or `~/.config/tmrc/config.yaml`). Renaming or copying the binary does not change behaviour. Exact default config location TBD (e.g. project root for dev, `~/.config/tmrc/` for installed CLI).

---

## 10. Observability & Debugging

- [x] 1. Metrics — **Out of scope for v1.** No optional counters (segments written, index lag, export count) or metrics export. Rely on logs and `tmrc status` only. State as non-goal; may revisit (e.g. file or Prometheus) later.
- [x] 2. Debug mode — **In scope for v1.** Provide **`tmrc --debug`** or **`TMRC_DEBUG=1`** (env var) to enable verbose logging; optionally preserve temporary files or dry-run for export. Document for support. Exact behaviour (log level, which subcommands respect it, temp file retention) TBD in implementation.
- [x] 3. Reproducibility — **`tmrc --version`** prints a version string (e.g. semver or git describe; format TBD). The **same version** is included in daemon and CLI logs to help diagnose issues.

---

## Progress (where we left off)

- **Sections 1–5 resolved** (Recording, Storage, Indexing, Ask, Export). **config.yaml** updated with: sample_rate_ms, display, capture_mode, audio_enabled, record_when_locked_or_sleeping, session, storage_root, index_mode, ocr_*, ask_default_range, export_quality.
- **All sections 1–10 resolved.** Architecture review complete; remaining work is optional (e.g. data-at-rest encryption to-do) and implementation.
- **To-do (optional):** Data-at-rest encryption — when enabled in config, key derivation from user password, key storage (e.g. keychain), and password-entry UX; full design and implementation later.

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
