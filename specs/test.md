# Test Items: Time Machine Recall Commander (tmrc)

Table of test cases for review and execution. Fill **Pass** when running tests.

## Part 1: devops.ps1 (Windows development script)

Table of test cases for the PowerShell devops script. Same columns: fill **Actual Result** and **Pass** when running tests.

| # | Category | Subject | Action Taken | Expected Result | Pass |
|---|----------|---------|----------------|---------------------|-----|
| D1 | Environment | No arguments (usage) | Run `./devops.ps1` with no command. | Script prints usage (commands: setup, build, test, record, etc.); exits 0. | ✓ |
| D2 | Environment | Unknown command | Run `./devops.ps1 unknown-cmd`. | Script exits non-zero; prints "Unknown command" and usage. | ✓ |
| D3 | Environment | DEVOPS_QUIET | Set `$env:DEVOPS_QUIET='1'`; run `./devops.ps1 setup`. | No `[ok]`/`[warn]` or `$ command` lines on stdout; only errors if any. | ✓ |
| D4 | Setup | setup / check-env | On Windows with .NET SDK and solution present, run `./devops.ps1 setup` (or `check-env`). | Exits 0; output includes "Operating system: Windows", ".NET SDK: ...", "Environment check passed." | ✓ |
| D5 | Setup | setup without solution | Run `./devops.ps1 setup` from a clone that has no `src\Tmrc.sln`. | Exits non-zero; message indicates Windows solution not found or planning mode. | ✓ |
| D6 | Setup | config.yaml reported | With no `config.yaml` at project root, run `./devops.ps1 setup`. | Warning about config.yaml not found; other checks still run. With config.yaml present, [ok] for config. | ✓ |
| D7 | Setup | ffprobe optional | Run setup with ffprobe not in PATH, then with ffprobe in PATH. | Without: warning that ffprobe not found; setup can still pass. With: [ok] for ffprobe. | ✓ |
| D8 | Build/Test | build | With solution at `src\Tmrc.sln`, run `./devops.ps1 build`. | Script runs `dotnet build` for the solution; exit code matches dotnet build (0 on success). | ✓ |
| D9 | Build/Test | test | With solution present, run `./devops.ps1 test`. | Script runs `dotnet test` for the solution; exit code matches dotnet test. | ✓ |
| D10 | Build/Test | clean | Run `./devops.ps1 clean`. | Script runs `dotnet clean` for the solution; exits 0; message indicates artifacts cleaned. | ✓ |
| D11 | Lint | lint with dotnet-format | With `dotnet-format` in PATH and solution present, run `./devops.ps1 lint`. | Script runs dotnet-format on the solution (or project); exit code matches formatter. | ✓ |
| D12 | Lint | lint without dotnet-format | With `dotnet-format` not in PATH, run `./devops.ps1 lint`. | Exits non-zero; message says dotnet-format is required and suggests install command. | ✓ |
| D13 | CLI delegation | record | Run `./devops.ps1 record` (with solution and CLI project present). | Script invokes tmrc CLI `record` via `dotnet run --project ... -- record`; behavior matches tmrc record. | ✓ |
| D14 | CLI delegation | status | Run `./devops.ps1 status`. | Script invokes tmrc CLI `status`; output reflects daemon state and/or usage. | ✓ |
| D15 | CLI delegation | dump | Run `./devops.ps1 dump`. | Script runs tmrc export for full range; output file path matches pattern `tmrc_dump_yyyy-MM-dd_HH-mm-ss.mp4` under project root. | ✓ |
| D16 | CLI delegation | wipe | Run `./devops.ps1 wipe`. | Script invokes tmrc `wipe`; recordings and index removed per tmrc behavior. | ✓ |
| D17 | CLI delegation | reindex | Run `./devops.ps1 reindex` and `./devops.ps1 reindex --force`. | Script invokes tmrc `reindex` (and passes `--force` through); no "unknown argument" from tmrc. | ✓ |
| D18 | Help | help command | Run `./devops.ps1 help`. | Same usage output as no-argument run; exits 0. | ✓ |

---

## Part 2: tmrc executable

| # | Category | Subject | Action Taken | Expected Result | Pass |
|---|----------|---------|----------------|---------------------|-----|
| 1 | Recording | Sample rate default | Create a config file (or in-memory YAML) with no `sample_rate_ms` key. Call the config loader with that config source. | Assert the loaded config’s `sample_rate_ms` (or equivalent property) equals 100. | ✓ |
| 2 | Recording | Sample rate override | Create a config file containing `sample_rate_ms: 16.1`. Call the config loader with that path (or content). | Assert the loaded config’s `sample_rate_ms` equals 16.1. | ✓ |
| 3 | Recording | Sample rate invalid | Create a config file with `sample_rate_ms: 0` (or negative). Call the config loader. | Assert load fails with validation error, or the loader returns a sensible default (e.g. 100); no crash. | ✓ |
| 4 | Recording | Segment boundaries (event-based) | In a test harness, feed a synthetic event stream: emit one event, then advance time by one frame with no events. Invoke the segment-boundary logic. | Assert at least one segment is flushed after the idle frame. | ✓ |
| 5 | Recording | Segment boundaries (burst) | Feed ~31 events at 32.2 ms intervals over ~1 s, then one frame with no events. Invoke the segment-boundary logic. | Assert one segment (or the expected count per spec) is flushed after the idle frame. | ✓ |
| 6 | Recording | Session name default | Load config with no `session` key. Start recording (or invoke the code path that resolves session name). | Assert the resolved session name is `"default"`. | ✓ |
| 7 | Recording | Session name from config | Set `session: work` in config and load. Start recording (or resolve session). | Assert the resolved session name is `work`. | ✓ |
| 8 | Recording | Session name CLI override | Set `session: default` in config. Run `tmrc record --session work` (or pass `--session work` to the CLI parser and resolve session). | Assert the session used for storage/daemon is `work`. | ✓ |
| 9 | Recording | Capture mode default | Load config with no `capture_mode`. | Assert the loaded `capture_mode` (or effective mode) is full_screen. | ✓ |
| 10 | Recording | Display default | Load config with no `display`. | Assert the effective display setting is main display only. | ✓ |
| 11 | Recording | Audio default | Load config with no `audio_enabled`. | Assert the loaded or effective `audio_enabled` is false. | ✓ |
| 12 | Recording | Audio enabled | Set `audio_enabled: true` in config. Start daemon with recording; let it run until at least one segment is written. | Assert audio segment files (or metadata) exist; segment duration/format consistent with 3 h segments for export. | ✓ |
| 13 | Recording | Lock/sleep default | Load config with no `record_when_locked_or_sleeping`. | Assert the effective value is false (do not record when locked or sleeping). | ✓ |
| 14 | Recording | Graceful shutdown (SIGTERM) | Start daemon with temp storage; write at least one in-memory buffer. Send SIGTERM to the daemon process. | Daemon process exits; before exit, segment files and index reflect the buffered data (e.g. one segment file created/updated). | ✓ |
| 15 | Recording | Graceful shutdown (SIGINT) | Start daemon with temp storage; send SIGINT (e.g. Ctrl+C) to the daemon. | Daemon exits; segment files and index synced (same as for SIGTERM). | ✓ |
| 16 | Storage | Storage root default | Load config with no `storage_root`. Resolve storage root path (e.g. via config loader or env). | Assert the resolved path equals `~/.tmrc/` expanded (e.g. `FileManager.default.homeDirectoryForCurrentUser` + `.tmrc` or equivalent). | ✓ |
| 17 | Storage | Storage root override | Set `storage_root: /tmp/tmrc-test` in config and load. Resolve storage root. | Assert the resolved path is `/tmp/tmrc-test`. | ✓ |
| 18 | Storage | Directory layout after install | Set env or config so storage_root is a temp dir. Run `tmrc install` (or the install code path). List the directory tree under storage_root. | Assert directories `index/` and segments dir exist; log file path exists; `tmrc.pid` does not exist until record is started. | ✓ |
| 19 | Storage | Index path per session | Resolve index file path for session name `default` and a given storage_root. | Assert path equals `storage_root/index/default.sqlite`. | ✓ |
| 20 | Storage | Index path for named session | Resolve index file path for session name `work` and a given storage_root. | Assert path equals `storage_root/index/work.sqlite`. | ✓ |
| 21 | Storage | Retention max age | Create temp storage; add mock segment files with timestamps older than max_age (e.g. 7 days). Run the retention/eviction logic. List segment files. | Assert the oldest segments are deleted; remaining segments are all within max_age. | ✓ |
| 22 | Storage | Retention max disk | Create temp storage; set max_disk to a small value; add mock segments until total size exceeds cap. Run retention. | Assert oldest segments are evicted until total size ≤ max_disk. | ✓ |
| 23 | Storage | Retention under limits | Add segments all within max_age and total size under max_disk. Run retention. | Assert no segment files are deleted. | ✓ |
| 24 | Storage | Disk full / low space | Create a read-only directory (or a volume at capacity). Set storage_root to that path; start daemon or attempt first write. | Process exits with non-zero; stderr or log contains a clear error message; no silent continue. Optionally assert a toast was triggered (if mock notifier captures it). | ✓ |
| 25 | Storage | Usage report | Run the subcommand that lists usage (e.g. `tmrc status` or a dedicated usage command). | Assert output includes disk usage (e.g. per session or total); format matches documentation. | ✓ |
| 26 | Storage | Index create and read | Start daemon (or a test helper) with temp storage_root; trigger write of one segment with known id, time range, and OCR text. Query the index by segment id or time range. | Assert the index returns that segment with the same id, time range, and text. | ✓ |
| 27 | Indexing | Index mode default | Load config with no `index_mode`. | Assert the loaded `index_mode` is a valid enum value (e.g. normal or advanced) as defined in spec. | ✓ |
| 28 | Indexing | Index mode advanced/normal | Load config with `index_mode: advanced`. Then load config with `index_mode: normal`. | Assert both loads succeed and the respective property equals the set value. | ✓ |
| 29 | Indexing | Index mode invalid | Load config with `index_mode: foo` (or another invalid string). | Assert load fails or returns a validation error; no crash. | ✓ |
| 30 | Indexing | OCR languages default | Load config with no `ocr_recognition_languages`. | Assert the loaded list includes `"en-US"`, `"zh-Hant"`, and `"zh-Hans"`. | ✓ |
| 31 | Indexing | OCR languages override | Set `ocr_recognition_languages: ["ja-JP", "ko-KR"]` in config and load. Run the indexer (or OCR config consumer) for one segment. | Assert the OCR layer is invoked with (or uses) the configured locales. | ✓ |
| 32 | Indexing | Index schema | Create a new index for a session (e.g. open or create the SQLite file and run schema migration). | Query SQLite for table names and optional schema version; assert expected tables and columns exist; version matches. | ✓ |
| 33 | Indexing | Index build failure (partial) | In a test, provide one segment that causes OCR/STT to fail (e.g. corrupt image or stub that returns error). Run the indexer for multiple segments including that one. | Assert the index contains entries for the successful segments; the failed segment is marked or omitted; user notification was triggered (toast or status in mock). | ✓ |
| 34 | Indexing | Rebuild index from segments | Place existing segment files in temp storage; run the rebuild-index subcommand or flag. | Assert a new or overwritten SQLite index exists; query by time or segment id returns rows for the segment files. | ✓ |
| 35 | Indexing | Re-index idempotency | Run the indexer on a fixed set of segments; note row count and checksum (or content). Run the indexer again on the same set. | Assert second run completes; no duplicate primary keys; row count or content is deterministic (overwrite semantics). | ✓ |
| 36 | Recall (Ask) | Query scope default | Run `tmrc ask "foo"` with no `--since` or `--until`. | Assert the search uses a time range equal to the config default (e.g. last 24h): e.g. inspect log, or stub the index query and assert the time bounds passed. | ✓ |
| 37 | Recall (Ask) | Query scope --since/--until | Run `tmrc ask "foo" --since "2h ago" --until "1h ago"`. | Assert the index/search is called with a range that corresponds to that 1-hour window (e.g. stub and assert arguments, or check log). | ✓ |
| 38 | Recall (Ask) | Time range parsing relative | Call the time-range parser with "now" fixed to a known instant; parse "1h ago" and "yesterday". | Assert the returned absolute start/end times match the expected range for that fixed "now". | ✓ |
| 39 | Recall (Ask) | Time range parsing absolute | Call the time-range parser with "2025-02-15 14:32:00" in local timezone. | Assert the returned range uses that instant correctly in local time (no wrong timezone conversion). | ✓ |
| 40 | Recall (Ask) | Citation format | Run `tmrc ask "query"` against an index that has matches. Capture stdout. | Assert output contains a timestamp in the form `YYYY-MM-DD HH:MM:SS` (24h) and segment ID or reference usable for export. | ✓ |
| 41 | Recall (Ask) | No results | Run `tmrc ask "nonexistentkeyword"` with a scope that has no matching segments. | Assert stdout or exit message states that there are no matches in the given scope (no generic crash or empty blob). | ✓ |
| 42 | Recall (Ask) | Multiple matches | Run `tmrc ask "query"` with an index that has several matching segments. | Assert the answer includes more than one citation (timestamps/segment refs); order or ranking matches config (e.g. by time or relevance). | ✓ |
| 43 | Recall (Export) | Export by time range | Create fixture segments and index for a known time range [T1, T2]. Run `tmrc export --from T1 --to T2 -o out.mp4`. | Assert `out.mp4` exists; run a duration check (e.g. ffprobe or AVFoundation) and assert duration is within expected range for [T1, T2]. | ✓ |
| 44 | Recall (Export) | Export --from/--to relative | With "now" and fixture data, run `tmrc export --from "1h ago" --to "30m ago" -o out.mp4`. | Assert the exported file spans the correct wall-clock range (e.g. check segment timestamps included or duration). | ✓ |
| 45 | Recall (Export) | Export by query | Create index with matches for query Q at times T1…Tn. Run `tmrc export --query "Q" -o out.mp4`. | Assert one output file; its time span equals [min(T1…Tn), max(T1…Tn)] (merged range); no extra segments outside that range. | ✓ |
| 46 | Recall (Export) | Stitch multiple segments | Create two or more segment files and index entries in order. Export a time range that spans all of them. | Assert output file exists; total duration is approximately the sum of segment durations; playable (or decode and assert frame count). | ✓ |
| 47 | Recall (Export) | Missing segment | Create index with a segment id S and time range; delete or omit the segment file for S. Run export for that time range. | Assert export exits non-zero; stderr or log contains a clear message that the segment is missing or export failed; no partial file or silent skip (per spec: fail with clear message). | ✓ |
| 48 | Recall (Export) | Export format MP4 | Export a range to `out.mp4` (default or `--format mp4`). | Assert file exists; container is MP4 and video codec is H.264 (e.g. ffprobe or similar). | ✓ |
| 49 | Recall (Export) | Export format GIF | Run `tmrc export --from T1 --to T2 --format gif -o out.gif`. | Assert `out.gif` exists and is a valid GIF (e.g. identify or decode first frame). | ✓ |
| 50 | Recall (Export) | Export quality levels | Export the same range with `low`, `medium`, and `high` (config or flag). Decode or probe each output. | Assert resolution and/or bitrate match spec (e.g. low ≈720p ~2 Mbps, high ≈1080p+ ~8 Mbps). | ✓ |
| 51 | Recall (Export) | Output path -o | Run `tmrc export ... -o /path/to/out.mp4` with a path that does not yet exist. | Assert the file is created at `/path/to/out.mp4`. | ✓ |
| 52 | Recall (Export) | Output path overwrite | Create an existing file at `out.mp4`. Run `tmrc export ... -o out.mp4`. | Assert no prompt; file is overwritten and export succeeds. | ✓ |
| 53 | Recall (Export) | Concurrent exports | Start 5–10 `tmrc export` processes in parallel (overlapping or different ranges) against the same storage. Wait for all to finish. | Assert all processes exit 0; all output files exist and are valid; index and segment files unchanged/correct (no corruption). | ✓ |
| 54 | Recall (Export) | Export while recording | Start daemon with mock or real capture; while recording, run one or more `tmrc export` for past ranges. | Assert exports complete and output files are valid; exports only read closed segments (e.g. no "file in use" or corrupt read); daemon continues recording. | ✓ |
| 55 | CLI & Daemon | Daemon start | Run `tmrc record` or `tmrc record --start` with temp storage_root. | Assert daemon process is running; `storage_root/tmrc.pid` exists and contains a valid PID; socket file exists. | ✓ |
| 56 | CLI & Daemon | Daemon already running | Start daemon; run `tmrc record --start` again. | Assert CLI exits with non-zero; stdout/stderr contains a message like "Recording is already in progress" or "Another tmrc recorder is already running". | ✓ |
| 57 | CLI & Daemon | Daemon discovery | With daemon running, run `tmrc record --status` or `tmrc status`. | Assert output indicates recording is in progress and (if applicable) shows the same PID as in tmrc.pid. | ✓ |
| 58 | CLI & Daemon | Daemon stop | Start daemon; run `tmrc record --stop`. | Assert daemon process is no longer running; tmrc.pid and socket file are removed (or stale PID is handled); segment data synced. | ✓ |
| 59 | CLI & Daemon | Subcommands parse | Invoke `tmrc record`, `tmrc record --start`, `tmrc ask "q"`, `tmrc export -o x`, `tmrc install`, `tmrc uninstall`, `tmrc status`. Then invoke `tmrc invalid`. | Assert each valid subcommand is accepted (exit 0 or appropriate); `tmrc invalid` exits non-zero and prints usage or error. | ✓ |
| 60 | CLI & Daemon | No arguments (usage) | Invoke `tmrc` with no arguments (no subcommand). | Assert process exits non-zero; stdout or stderr contains usage or help (e.g. subcommand list or --help output). | ✓ |
| 61 | CLI & Daemon | --version | Run `tmrc --version`. | Assert stdout prints a version string (e.g. semver or git describe); exit 0. | ✓ |
| 62 | CLI & Daemon | Config location (dev) | Place config.yaml in project root; run the CLI from project root (or set cwd to project root in test). | Assert config is loaded (e.g. a config-dependent command succeeds or log shows config path). | ✓ |
| 63 | CLI & Daemon | Config location (installed) | Run the installed binary with no env override; ensure no config in project root. | Assert config is loaded from default installed location (e.g. ~/.config/tmrc/config.yaml) or document env override and assert that works. | ✓ |
| 64 | CLI & Daemon | Log file | Start daemon and run one CLI command (e.g. status). Read the log file under storage_root. | Assert a single log file (e.g. tmrc.log) exists and contains lines from both daemon and CLI (e.g. distinct messages or timestamps). | ✓ |
| 65 | CLI & Daemon | Log rotation | Run daemon and/or CLI long enough to trigger rotation, or simulate time-based rotation (e.g. set rotation to 1 day and advance clock). | Assert after rotation only one active log file exists; older content retained per 7-day policy (or overwritten per spec). | ✓ |
| 66 | CLI & Daemon | Upgrade while running | Start daemon; replace the tmrc binary on disk with a new build; run `tmrc status`. | Assert the existing daemon process is still running (same PID); no automatic restart; document that user must stop/start to use new binary. | ✓ |
| 67 | Security | Data at rest default | Load config with no encryption-related key. | Assert encryption is disabled (e.g. segments are written unencrypted; no key derivation). | ✓ |
| 68 | Security | Read-only storage_root | Create a read-only directory; set storage_root to it; run `tmrc record --start` or daemon. | Assert startup or first write fails immediately with a clear error (no retry loop); exit non-zero. | ✓ |
| 69 | Security | Access control | Create storage_root and index/segments as the running user. Check file permissions (e.g. `ls -la` or FileManager). | Assert only the owning user has read (and write) access; no world-readable or overly permissive bits. | ✓ |
| 70 | Operations | Install | Run `tmrc install` with config pointing to a temp storage_root (or default). | Assert directories (e.g. storage_root, index/, segments) exist; if no config existed, a default config file is created at the expected location. | ✓ |
| 71 | Operations | Uninstall (keep data) | Run `tmrc install` then `tmrc uninstall` without --remove-data. | Assert daemon is stopped; storage_root and its contents (index, segments) still exist. | ✓ |
| 72 | Operations | Uninstall (remove data) | Run `tmrc uninstall --remove-data`. | Assert daemon stopped; storage_root and its subdirs/files are removed (or as specified). | ✓ |
| 73 | Operations | Status daemon running | Start daemon; run `tmrc status`. | Assert output includes "recording" or equivalent true; last segment time (if any); disk usage. | ✓ |
| 74 | Operations | Status daemon stopped | Stop daemon (or do not start); run `tmrc status`. | Assert output indicates not recording; disk usage still shown if data exists. | ✓ |
| 75 | Operations | Status last recording (total duration) | Create index with multiple segments (e.g. 3 segments with durations 5 min, 10 min, 8 min). Run `tmrc status`. | "Last recording" shows total recorded duration (e.g. 00:00:23:00 for 23 min sum), not only the last segment’s duration (e.g. 00:00:08:00 or 00:00:00:01). | ✓ |
| 76 | Operations | Crash recovery | Start daemon; kill it with SIGKILL (or force quit). Restart daemon. | Assert on restart a new session starts (no resume); any partial segment file from the killed run is ignored or deleted (do not use for export/index). | ✓ |
| 77 | Operations | Monotonic vs wall-clock | In a test, provide segments with both monotonic and wall-clock timestamps. Run export or ask for a wall-clock range. | Assert segment ordering uses monotonic time; exported file or displayed timestamps use wall-clock (local time). | ✓ |
| 78 | Edge Conditions | Ask with empty index | Run `tmrc install` (no prior recording); run `tmrc ask "anything"`. | Assert a friendly message (e.g. no matches or index empty); optionally suggests waiting or checking status; no crash. | ✓ |
| 79 | Edge Conditions | Overlapping segments | Create two segments with overlapping time ranges (e.g. [10:00, 10:05] and [10:02, 10:07]). Export or ask for that range. | Assert the chosen segment for the overlap is the newer one (e.g. by segment id or timestamp); no duplicate or wrong segment. | ✓ |
| 80 | Edge Conditions | Binary rename | Copy tmrc to another path (e.g. /tmp/tmrc-copy); run the copy with same args (e.g. status or record --start). | Assert daemon discovery and config resolution use the same paths as the original (e.g. storage_root from config/env, not binary location). | ✓ |
| 81 | Edge Conditions | Long session | Run daemon with mock capture for 2+ hours (or configured retention window). | Assert daemon stays alive; retention evicts old segments as configured; no crash or OOM. | ✓ |
| 82 | Observability | Version in logs | Run daemon or CLI; read the log file. | Assert the same string printed by `tmrc --version` appears in the log (e.g. in startup line). | ✓ |
| 83 | Observability | Debug mode | Run `tmrc --debug status` or `TMRC_DEBUG=1 tmrc status`. Read log or stderr. | Assert log level is verbose (more lines or DEBUG); process exits 0; no crash. | ✓ |
| 84 | Soak | Daemon long run | Run daemon with mock or minimal real capture for 30–60 min. Periodically sample segment count and index row count. | At end: process still running; segment file count equals index row count (or consistent per spec); no duplicate segment IDs in index; memory growth within acceptable bound. | ✓ |
| 86 | Soak | Concurrent exports stress | Run 10+ `tmrc export` in parallel; wait for all. | All exit 0; all output files exist and are valid (duration/codec); index and segment files unchanged; no corruption. | ✓ |

---

## Notes for review

- **Action Taken:** What to do in order (create files, run commands, call APIs).
- **Expected Result:** How to verify (assert in code, inspect file/log, check exit code, probe media).
- **Pass:** Use e.g. ✓ / ✗ or Yes / No after execution.
- Some items may require real capture, long run, or soak; mark as E2E/soak as needed.
- Add or remove rows as you refine; renumber if desired.
