# Test Items: Time Machine Recall Commander (tmrc)

Table of test cases for review and execution. Fill **Actual Result** and **Pass** when running tests.

| # | Category | Subject | Action Taken | Expected Result | Actual Result | Pass |
|---|----------|---------|----------------|---------------------|---------------|-----|
| 1 | Recording | Sample rate default | Create a config file (or in-memory YAML) with no `sample_rate_ms` key. Call the config loader with that config source. | Assert the loaded config's `sample_rate_ms` (or equivalent property) equals 100. |
| 2 | Recording | Sample rate override | Create a config file containing `sample_rate_ms: 16.1`. Call the config loader with that path (or content). | Assert the loaded config's `sample_rate_ms` equals 16.1. |
| 3 | Recording | Sample rate invalid | Create a config file with `sample_rate_ms: 0` (or negative). Call the config loader. | Assert load fails with validation error, or the loader returns a sensible default (e.g. 100); no crash. |
| 4 | Recording | Segment boundaries (event-based) | In a test harness, feed a synthetic event stream: emit one event, then advance time by one frame with no events. Invoke the segment-boundary logic. | Assert at least one segment is flushed after the idle frame. |
| 5 | Recording | Segment boundaries (burst) | Feed ~31 events at 32.2 ms intervals over ~1 s, then one frame with no events. Invoke the segment-boundary logic. | Assert one segment (or the expected count per spec) is flushed after the idle frame. |
| 6 | Recording | Session name default | Load config with no `session` key. Start recording (or invoke the code path that resolves session name). | Assert the resolved session name is `"default"`. |
| 7 | Recording | Session name from config | Set `session: work` in config and load. Start recording (or resolve session). | Assert the resolved session name is `work`. |
| 8 | Recording | Session name CLI override | Set `session: default` in config. Run `tmrc record --session work` (or pass `--session work` to the CLI parser and resolve session). | Assert the session used for storage/daemon is `work`. |
| 9 | Recording | Capture mode default | Load config with no `capture_mode`. | Assert the loaded `capture_mode` (or effective mode) is full_screen. |
| 10 | Recording | Capture mode override | Set `capture_mode: window` in config and load. | Assert the loaded `capture_mode` equals `window`; no validation error. |
| 11 | Recording | Display default | Load config with no `display`. | Assert the effective display setting is main display only. |
| 12 | Recording | Display override | Set `display: all` in config and load. | Assert the loaded `display` equals `all`; no validation error. |
| 13 | Recording | Audio default | Load config with no `audio_enabled`. | Assert the loaded or effective `audio_enabled` is false. |
| 14 | Recording | Audio enabled | Set `audio_enabled: true` in config. Start daemon with recording; let it run until at least one segment is written. | Assert audio segment files (or metadata) exist; segment duration/format consistent with 3 h segments for export. |
| 15 | Recording | Lock/sleep default | Load config with no `record_when_locked_or_sleeping`. | Assert the effective value is false (do not record when locked or sleeping). |
| 16 | Recording | Lock/sleep override | Set `record_when_locked_or_sleeping: true` in config and load. | Assert the loaded value is true; no validation error. |
| 17 | Recording | Permission before start | Run `tmrc record --start` on a system where Screen Recording has not been granted. | Observe system permission prompt; daemon does not start (no PID file) until user grants permission. |
| 18 | Recording | Permission revoked mid-session | Start recording with permission granted. Revoke Screen Recording in System Settings while daemon is running. | Observe a toast notification; within a short time daemon exits; list storage and assert latest segment was synced (file exists and is complete). |
| 19 | Recording | Graceful shutdown (SIGTERM) | Start daemon with temp storage; write at least one in-memory buffer. Send SIGTERM to the daemon process. | Daemon process exits; before exit, segment files and index reflect the buffered data (e.g. one segment file created/updated). |
| 20 | Recording | Graceful shutdown (SIGINT) | Start daemon with temp storage; send SIGINT (e.g. Ctrl+C) to the daemon. | Daemon exits; segment files and index synced (same as for SIGTERM). |
| 21 | Recording | Capture native resolution | On a display with backing scale > 1 (e.g. Retina), start recording and write at least one segment. Probe the segment file (e.g. ffprobe) for video width/height. | Assert segment resolution equals display native pixel dimensions (logical size × backing scale); not limited to logical resolution only (e.g. 2880×1800 not 1440×900 on a 15" Retina). |
| 22 | Recording | Static screen no new segment | Start recording; feed identical (unchanged) frames for several sample intervals with no events. | Assert no new segment is created for the static period; event-based model produces segments only when events occur (spec 2.7). |
| 23 | Recording | Segment format without FFmpeg | Remove or hide FFmpeg from PATH; start recording and let one segment close. | Assert the segment is stored as `.bin` placeholder (not `.mp4`); no crash; log indicates FFmpeg is unavailable. |

| # | Category | Subject | Action Taken | Expected Result | Actual Result | Pass |
|---|----------|---------|----------------|---------------------|---------------|-----|
| 24 | Storage | Storage root default | Load config with no `storage_root`. Resolve storage root path (e.g. via config loader or env). | Assert the resolved path equals `%USERPROFILE%\.tmrc` expanded (or `~/.tmrc/` on other platforms). |
| 25 | Storage | Storage root override | Set `storage_root: /tmp/tmrc-test` in config and load. Resolve storage root. | Assert the resolved path is `/tmp/tmrc-test`. |
| 26 | Storage | Directory layout after install | Set env or config so storage_root is a temp dir. Run `tmrc install` (or the install code path). List the directory tree under storage_root. | Assert directories `index/` and segments dir exist; log file path exists; `tmrc.pid` does not exist until record is started. |
| 27 | Storage | Index path per session | Resolve index file path for session name `default` and a given storage_root. | Assert path equals `storage_root/index/default.sqlite`. |
| 28 | Storage | Index path for named session | Resolve index file path for session name `work` and a given storage_root. | Assert path equals `storage_root/index/work.sqlite`. |
| 29 | Storage | Retention max age default | Load config with no `retention_max_age_days`. | Assert the loaded default equals 30 (days). |
| 30 | Storage | Retention max disk default | Load config with no `retention_max_disk_bytes`. | Assert the loaded default equals 53687091200 (50 GB in bytes). |
| 31 | Storage | Retention max age eviction | Create temp storage; add mock segment files with timestamps older than max_age (e.g. 7 days). Run the retention/eviction logic. List segment files. | Assert the oldest segments are deleted; remaining segments are all within max_age. |
| 32 | Storage | Retention max disk eviction | Create temp storage; set max_disk to a small value; add mock segments until total size exceeds cap. Run retention. | Assert oldest segments are evicted until total size ≤ max_disk. |
| 33 | Storage | Retention under limits | Add segments all within max_age and total size under max_disk. Run retention. | Assert no segment files are deleted. |
| 34 | Storage | Retention index pruning | Create temp storage with segments and matching index rows. Run retention so that some segments are evicted. Query the index. | Assert index rows for evicted segments are also removed; remaining index rows reference only existing segment files. |
| 35 | Storage | Disk full / low space | Create a read-only directory (or a volume at capacity). Set storage_root to that path; start daemon or attempt first write. | Process exits with non-zero; stderr or log contains a clear error message; no silent continue. Optionally assert a toast was triggered (if mock notifier captures it). |
| 36 | Storage | Usage report | Run the subcommand that lists usage (e.g. `tmrc status` or a dedicated usage command). | Assert output includes disk usage (e.g. per session or total); format matches documentation. |
| 37 | Storage | Index create and read | Start daemon (or a test helper) with temp storage_root; trigger write of one segment with known id, time range, and OCR text. Query the index by segment id or time range. | Assert the index returns that segment with the same id, time range, and text. |
| 38 | Storage | Wipe segments | Run `tmrc wipe` with a storage_root containing segment files and index data. | Assert all files under `segments/` are removed; command exits 0; index may or may not be cleared (per implementation). |

| # | Category | Subject | Action Taken | Expected Result | Actual Result | Pass |
|---|----------|---------|----------------|---------------------|---------------|-----|
| 39 | Indexing | Index mode default | Load config with no `index_mode`. | Assert the loaded `index_mode` is a valid enum value (e.g. normal or advanced) as defined in spec. |
| 40 | Indexing | Index mode advanced/normal | Load config with `index_mode: advanced`. Then load config with `index_mode: normal`. | Assert both loads succeed and the respective property equals the set value. |
| 41 | Indexing | Index mode invalid | Load config with `index_mode: foo` (or another invalid string). | Assert load fails or returns a validation error; no crash. |
| 42 | Indexing | OCR languages default | Load config with no `ocr_recognition_languages`. | Assert the loaded list includes `"en-US"`, `"zh-Hant"`, and `"zh-Hans"`. |
| 43 | Indexing | OCR languages override | Set `ocr_recognition_languages: ["ja-JP", "ko-KR"]` in config and load. Run the indexer (or OCR config consumer) for one segment. | Assert the OCR layer is invoked with (or uses) the configured locales. |
| 44 | Indexing | OCR language mapping | Call the BCP 47 → Tesseract code mapping function with inputs: `en-US`, `zh-Hant`, `zh-Hans`, `ja-JP`, `ko-KR`, `de-DE`. | Assert outputs are `eng`, `chi_tra`, `chi_sim`, `jpn`, `kor`, `de-DE` (pass-through for unmapped). |
| 45 | Indexing | Index schema | Create a new index for a session (e.g. open or create the SQLite file and run schema migration). | Query SQLite for table names and optional schema version; assert expected tables and columns exist; version matches. |
| 46 | Indexing | Index build failure (partial) | In a test, provide one segment that causes OCR/STT to fail (e.g. corrupt image or stub that returns error). Run the indexer for multiple segments including that one. | Assert the index contains entries for the successful segments; the failed segment is marked or omitted; user notification was triggered (toast or status in mock). |
| 47 | Indexing | Rebuild index from segments | Place existing segment files in temp storage; run the rebuild-index subcommand or flag. | Assert a new or overwritten SQLite index exists; query by time or segment id returns rows for the segment files. |
| 48 | Indexing | Re-index idempotency | Run the indexer on a fixed set of segments; note row count and checksum (or content). Run the indexer again on the same set. | Assert second run completes; no duplicate primary keys; row count or content is deterministic (overwrite semantics). |
| 49 | Indexing | Reindex CLI default | Create segments where some have OCR text and some do not. Run `tmrc reindex` (no `--force`). | Assert only segments with empty/missing OCR text are re-processed; segments with existing OCR text are skipped. |
| 50 | Indexing | Reindex CLI --force | Create segments where all have existing OCR text. Run `tmrc reindex --force`. | Assert all segments are re-processed regardless of existing OCR text; updated OCR text is written to index. |

| # | Category | Subject | Action Taken | Expected Result | Actual Result | Pass |
|---|----------|---------|----------------|---------------------|---------------|-----|
| 51 | Recall (Ask) | Ask default range config | Load config with no `ask_default_range`. | Assert the loaded default equals `"24h"` (or equivalent 24-hour representation). |
| 52 | Recall (Ask) | Query scope default | Run `tmrc ask "foo"` with no `--since` or `--until`. | Assert the search uses a time range equal to the config default (e.g. last 24h): e.g. inspect log, or stub the index query and assert the time bounds passed. |
| 53 | Recall (Ask) | Query scope --since/--until | Run `tmrc ask "foo" --since "2h ago" --until "1h ago"`. | Assert the index/search is called with a range that corresponds to that 1-hour window (e.g. stub and assert arguments, or check log). |
| 54 | Recall (Ask) | Time range parsing relative | Call the time-range parser with "now" fixed to a known instant; parse "1h ago" and "yesterday". | Assert the returned absolute start/end times match the expected range for that fixed "now". |
| 55 | Recall (Ask) | Time range parsing absolute | Call the time-range parser with "2025-02-15 14:32:00" in local timezone. | Assert the returned range uses that instant correctly in local time (no wrong timezone conversion). |
| 56 | Recall (Ask) | Citation format | Run `tmrc ask "query"` against an index that has matches. Capture stdout. | Assert output contains a timestamp in the form `YYYY-MM-DD HH:MM:SS` (24h) and segment ID or reference usable for export. |
| 57 | Recall (Ask) | No results | Run `tmrc ask "nonexistentkeyword"` with a scope that has no matching segments. | Assert stdout or exit message states that there are no matches in the given scope (no generic crash or empty blob). |
| 58 | Recall (Ask) | Multiple matches | Run `tmrc ask "query"` with an index that has several matching segments. | Assert the answer includes more than one citation (timestamps/segment refs); order or ranking matches config (e.g. by time or relevance). |

| # | Category | Subject | Action Taken | Expected Result | Actual Result | Pass |
|---|----------|---------|----------------|---------------------|---------------|-----|
| 59 | Recall (Export) | Export by time range | Create fixture segments and index for a known time range [T1, T2]. Run `tmrc export --from T1 --to T2 -o out.mp4`. | Assert `out.mp4` exists; run a duration check (e.g. ffprobe or AVFoundation) and assert duration is within expected range for [T1, T2]. |
| 60 | Recall (Export) | Export --from/--to relative | With "now" and fixture data, run `tmrc export --from "1h ago" --to "30m ago" -o out.mp4`. | Assert the exported file spans the correct wall-clock range (e.g. check segment timestamps included or duration). |
| 61 | Recall (Export) | Export by query | Create index with matches for query Q at times T1…Tn. Run `tmrc export --query "Q" -o out.mp4`. | Assert one output file; its time span equals [min(T1…Tn), max(T1…Tn)] (merged range); no extra segments outside that range. |
| 62 | Recall (Export) | Export query --since/--until | Create index with matches for query Q. Run `tmrc export --query "Q" --since "2h ago" --until "1h ago" -o out.mp4`. | Assert export only includes segments matching Q within the specified time window; segments outside that window are excluded. |
| 63 | Recall (Export) | Stitch multiple segments | Create two or more segment files and index entries in order. Export a time range that spans all of them. | Assert output file exists; total duration is approximately the sum of segment durations; playable (or decode and assert frame count). |
| 64 | Recall (Export) | Missing segment | Create index with a segment id S and time range; delete or omit the segment file for S. Run export for that time range. | Assert export exits non-zero; stderr or log contains a clear message that the segment is missing or export failed; no partial file or silent skip (per spec 9.4: fail with clear message). |
| 65 | Recall (Export) | Export format MP4 | Export a range to `out.mp4` (default or `--format mp4`). | Assert file exists; container is MP4 and video codec is H.264 (e.g. ffprobe or similar). |
| 66 | Recall (Export) | Export format GIF | Run `tmrc export --from T1 --to T2 --format gif -o out.gif`. | Assert `out.gif` exists and is a valid GIF (e.g. identify or decode first frame). |
| 67 | Recall (Export) | Export format manifest | Run `tmrc export --from T1 --to T2 --format manifest -o out.txt`. | Assert `out.txt` exists and contains a list of segment file paths (one per line or structured); no video encoding performed. |
| 68 | Recall (Export) | Export quality levels | Export the same range with `low`, `medium`, and `high` (config or flag). Decode or probe each output. | Assert resolution and/or bitrate match spec (e.g. low ≈720p ~2 Mbps, high ≈1080p+ ~8 Mbps). |
| 69 | Recall (Export) | Export quality default config | Load config with no `export_quality`. | Assert the loaded default equals `"high"`. |
| 70 | Recall (Export) | Export quality invalid config | Load config with `export_quality: ultra` (invalid value). | Assert load fails with validation error or returns a sensible default; no crash. |
| 71 | Recall (Export) | Output path -o | Run `tmrc export ... -o /path/to/out.mp4` with a path that does not yet exist. | Assert the file is created at `/path/to/out.mp4`. |
| 72 | Recall (Export) | Output path overwrite | Create an existing file at `out.mp4`. Run `tmrc export ... -o out.mp4`. | Assert no prompt; file is overwritten and export succeeds. |
| 73 | Recall (Export) | Output path default (no -o) | Run `tmrc export --from T1 --to T2` without `-o`. | Assert output file is written to the current directory with a generated filename containing session name and time range; file exists. |
| 74 | Recall (Export) | Concurrent exports | Start 5–10 `tmrc export` processes in parallel (overlapping or different ranges) against the same storage. Wait for all to finish. | Assert all processes exit 0; all output files exist and are valid; index and segment files unchanged/correct (no corruption). |
| 75 | Recall (Export) | Export while recording | Start daemon with mock or real capture; while recording, run one or more `tmrc export` for past ranges. | Assert exports complete and output files are valid; exports only read closed segments (e.g. no "file in use" or corrupt read); daemon continues recording. |

| # | Category | Subject | Action Taken | Expected Result | Actual Result | Pass |
|---|----------|---------|----------------|---------------------|---------------|-----|
| 76 | CLI & Daemon | Daemon start | Run `tmrc record` or `tmrc record --start` with temp storage_root. | Assert daemon process is running; `storage_root/tmrc.pid` exists and contains a valid PID; socket file exists. |
| 77 | CLI & Daemon | Daemon already running | Start daemon; run `tmrc record --start` again. | Assert CLI exits with non-zero; stdout/stderr contains a message like "Recording is already in progress" or "Another tmrc recorder is already running". |
| 78 | CLI & Daemon | Daemon discovery | With daemon running, run `tmrc record --status` or `tmrc status`. | Assert output indicates recording is in progress and (if applicable) shows the same PID as in tmrc.pid. |
| 79 | CLI & Daemon | Daemon stop | Start daemon; run `tmrc record --stop`. | Assert daemon process is no longer running; tmrc.pid and socket file are removed (or stale PID is handled); segment data synced. |
| 80 | CLI & Daemon | Subcommands parse | Invoke `tmrc record`, `tmrc record --start`, `tmrc ask "q"`, `tmrc export -o x`, `tmrc install`, `tmrc uninstall`, `tmrc status`, `tmrc wipe`, `tmrc reindex`. Then invoke `tmrc invalid`. | Assert each valid subcommand is accepted (exit 0 or appropriate); `tmrc invalid` exits non-zero and prints usage or error. |
| 81 | CLI & Daemon | No arguments (usage) | Invoke `tmrc` with no arguments (no subcommand). | Assert process exits non-zero; stdout or stderr contains usage or help (e.g. subcommand list or --help output). |
| 82 | CLI & Daemon | --version | Run `tmrc --version`. | Assert stdout prints a version string (e.g. semver or git describe); exit 0. |
| 83 | CLI & Daemon | Config location (dev) | Place config.yaml in project root; run the CLI from project root (or set cwd to project root in test). | Assert config is loaded (e.g. a config-dependent command succeeds or log shows config path). |
| 84 | CLI & Daemon | Config location (installed) | Run the installed binary with no env override; ensure no config in project root. | Assert config is loaded from default installed location (e.g. ~/.config/tmrc/config.yaml) or document env override and assert that works. |
| 85 | CLI & Daemon | Log level default | Load config with no `log_level`. | Assert the loaded default equals `"info"`. |
| 86 | CLI & Daemon | Log level invalid | Load config with `log_level: verbose` (invalid value). | Assert load fails with validation error or falls back to default; no crash. |
| 87 | CLI & Daemon | Log file | Start daemon and run one CLI command (e.g. status). Read the log file under storage_root. | Assert a single log file (e.g. tmrc.log) exists and contains lines from both daemon and CLI (e.g. distinct messages or timestamps). |
| 88 | CLI & Daemon | Log rotation | Run daemon and/or CLI long enough to trigger rotation, or simulate time-based rotation (e.g. set rotation to 1 day and advance clock). | Assert after rotation only one active log file exists; older content retained per 7-day policy (or overwritten per spec). |
| 89 | CLI & Daemon | Upgrade while running | Start daemon; replace the tmrc binary on disk with a new build; run `tmrc status`. | Assert the existing daemon process is still running (same PID); no automatic restart; document that user must stop/start to use new binary. |

| # | Category | Subject | Action Taken | Expected Result | Actual Result | Pass |
|---|----------|---------|----------------|---------------------|---------------|-----|
| 90 | Security | Data at rest default | Load config with no encryption-related key. | Assert encryption is disabled (e.g. segments are written unencrypted; no key derivation). |
| 91 | Security | Read-only storage_root | Create a read-only directory; set storage_root to it; run `tmrc record --start` or daemon. | Assert startup or first write fails immediately with a clear error (no retry loop); exit non-zero. |
| 92 | Security | Access control | Create storage_root and index/segments as the running user. Check file permissions (e.g. `ls -la` or FileManager). | Assert only the owning user has read (and write) access; no world-readable or overly permissive bits. |

| # | Category | Subject | Action Taken | Expected Result | Actual Result | Pass |
|---|----------|---------|----------------|---------------------|---------------|-----|
| 93 | Operations | Install | Run `tmrc install` with config pointing to a temp storage_root (or default). | Assert directories (e.g. storage_root, index/, segments) exist; if no config existed, a default config file is created at the expected location. |
| 94 | Operations | Uninstall (keep data) | Run `tmrc install` then `tmrc uninstall` without --remove-data. | Assert daemon is stopped; storage_root and its contents (index, segments) still exist. |
| 95 | Operations | Uninstall (remove data) | Run `tmrc uninstall --remove-data`. | Assert daemon stopped; storage_root and its subdirs/files are removed (or as specified). |
| 96 | Operations | Status daemon running | Start daemon; run `tmrc status`. | Assert output includes "recording" or equivalent true; last segment time (if any); disk usage. |
| 97 | Operations | Status daemon stopped | Stop daemon (or do not start); run `tmrc status`. | Assert output indicates not recording; disk usage still shown if data exists. |
| 98 | Operations | Status last recording (total duration) | Create index with multiple segments (e.g. 3 segments with durations 5 min, 10 min, 8 min). Run `tmrc status`. | "Last recording" shows total recorded duration (e.g. 00:00:23:00 for 23 min sum), not only the last segment's duration (e.g. 00:00:08:00 or 00:00:00:01). |
| 99 | Operations | Crash recovery | Start daemon; kill it with SIGKILL (or force quit). Restart daemon. | Assert on restart a new session starts (no resume); any partial segment file from the killed run is ignored or deleted (do not use for export/index). |
| 100 | Operations | Monotonic vs wall-clock | In a test, provide segments with both monotonic and wall-clock timestamps. Run export or ask for a wall-clock range. | Assert segment ordering uses monotonic time; exported file or displayed timestamps use wall-clock (local time). |

| # | Category | Subject | Action Taken | Expected Result | Actual Result | Pass |
|---|----------|---------|----------------|---------------------|---------------|-----|
| 101 | Edge Conditions | Ask with empty index | Run `tmrc install` (no prior recording); run `tmrc ask "anything"`. | Assert a friendly message (e.g. no matches or index empty); optionally suggests waiting or checking status; no crash. |
| 102 | Edge Conditions | Overlapping segments | Create two segments with overlapping time ranges (e.g. [10:00, 10:05] and [10:02, 10:07]). Export or ask for that range. | Assert the chosen segment for the overlap is the newer one (e.g. by segment id or timestamp); no duplicate or wrong segment. |
| 103 | Edge Conditions | Binary rename | Copy tmrc to another path (e.g. /tmp/tmrc-copy); run the copy with same args (e.g. status or record --start). | Assert daemon discovery and config resolution use the same paths as the original (e.g. storage_root from config/env, not binary location). |
| 104 | Edge Conditions | Long session | Run daemon with mock capture for 2+ hours (or configured retention window). | Assert daemon stays alive; retention evicts old segments as configured; no crash or OOM. |
| 105 | Edge Conditions | Toast notification on error | Simulate a write error during recording (e.g. fill disk or revoke write permission mid-session). Use a mock notifier. | Assert toast notification is triggered with an actionable message; daemon syncs and exits; mock notifier captures the notification content. |

| # | Category | Subject | Action Taken | Expected Result | Actual Result | Pass |
|---|----------|---------|----------------|---------------------|---------------|-----|
| 106 | Observability | Version in logs | Run daemon or CLI; read the log file. | Assert the same string printed by `tmrc --version` appears in the log (e.g. in startup line). |
| 107 | Observability | Debug mode | Run `tmrc --debug status` or `TMRC_DEBUG=1 tmrc status`. Read log or stderr. | Assert log level is verbose (more lines or DEBUG); process exits 0; no crash. |

| # | Category | Subject | Action Taken | Expected Result | Actual Result | Pass |
|---|----------|---------|----------------|---------------------|---------------|-----|
| 108 | DevOps | devops.ps1 setup | Run `./devops.ps1 setup` on a machine with .NET SDK installed. | Assert exit 0; output contains `[ok]` lines for OS and .NET SDK; warns for optional missing tools (ffprobe, dotnet-format). |
| 109 | DevOps | devops.ps1 dump (happy path) | Ensure FFmpeg is on PATH and MP4 segments exist in storage. Run `./devops.ps1 dump`. | Assert exit 0; a file named `tmrc_dump_<timestamp>.mp4` is created in the project root; file is a valid MP4. |
| 110 | DevOps | devops.ps1 dump (no segments) | Ensure storage has no MP4 segments. Run `./devops.ps1 dump`. | Assert command exits non-zero or produces an empty/zero-byte file with a clear message; no crash. |
| 111 | DevOps | devops.ps1 wipe | Create segment files in storage. Run `./devops.ps1 wipe`. | Assert all segment files under `segments/` are removed; exit 0. |
| 112 | DevOps | devops.ps1 reindex | Create segments with missing OCR text. Run `./devops.ps1 reindex`. | Assert segments without OCR are re-processed; exit 0 (requires Tesseract and FFmpeg). |
| 113 | DevOps | devops.ps1 reindex --force | Create segments with existing OCR text. Run `./devops.ps1 reindex --force`. | Assert all segments are re-processed; exit 0. |
| 114 | DevOps | devops.ps1 clear-tests | Populate Pass column in `specs/test.md` with values. Run `./devops.ps1 clear-tests`. | Assert all Pass column values are cleared; other columns (Actual Result, etc.) are unchanged; exit 0. |
| 115 | DevOps | devops.ps1 help / no args | Run `./devops.ps1 help` and `./devops.ps1` (no args). | Assert both print usage listing all commands; exit 0. |
| 116 | DevOps | devops.ps1 invalid command | Run `./devops.ps1 foobar`. | Assert exit non-zero; output contains error message and usage. |

| # | Category | Subject | Action Taken | Expected Result | Actual Result | Pass |
|---|----------|---------|----------------|---------------------|---------------|-----|
| 117 | Soak | Daemon long run | Run daemon with mock or minimal real capture for 30–60 min. Periodically sample segment count and index row count. | At end: process still running; segment file count equals index row count (or consistent per spec); no duplicate segment IDs in index; memory growth within acceptable bound. |
| 118 | Soak | Concurrent exports stress | Run 10+ `tmrc export` in parallel; wait for all. | All exit 0; all output files exist and are valid (duration/codec); index and segment files unchanged; no corruption. |

---

## Notes for review

- **Action Taken:** What to do in order (create files, run commands, call APIs).
- **Expected Result:** How to verify (assert in code, inspect file/log, check exit code, probe media).
- **Actual Result:** Fill when the test is executed (e.g. "Passed", "Failed: ...", or brief description).
- **Pass:** Use e.g. ✓ / ✗ or Yes / No after execution.
- Items 17–18, 21–22, 35, 74–75, 89, 103–104 may require real capture, permissions, or long run; mark as E2E/soak as needed.
- Add or remove rows as you refine; renumber if desired.
