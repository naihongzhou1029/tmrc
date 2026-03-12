# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

Use `devops.sh` as the single entry point for all development operations:

```bash
./devops.sh build          # swift build (debug)
./devops.sh test           # swift test
./devops.sh lint           # swiftlint (if installed)
./devops.sh clean          # swift package clean
./devops.sh release <vX.Y.Z>  # release build + zip in dist/
```

Direct Swift commands also work:
```bash
swift build                # debug build
swift build -c release     # release build
swift test                 # all tests
swift test --filter <TestName>  # single test
```

Debug binary: `.build/arm64-apple-macosx/debug/tmrc`
Release binary: `.build/arm64-apple-macosx/release/tmrc`

The `tmrc` symlink in the project root points to the debug binary for convenience.

## Architecture

**tmrc** is a macOS CLI tool (Swift, Apple Silicon, macOS 13+) for screen recording, indexing, and recall. Three subsystems:

### 1. Daemon (background recorder)
- `Sources/tmrc/Daemon/` — `DaemonRunner.swift` hosts the main capture loop; `DaemonManager.swift` manages start/stop/PID; `DaemonEntry.swift` is the daemon mode entrypoint
- `Sources/tmrc/Capture/` — `ScreenCaptureService.swift` uses ScreenCaptureKit; `EventSegmenter.swift` flushes segments on event boundaries (default 100ms); `SegmentWriter.swift` writes H.264 MP4 via AVAssetWriter
- After each segment closes, `OCRService.swift` (Index/) runs Vision `VNRecognizeTextRequest` and upserts into SQLite

### 2. Index pipeline
- `Sources/tmrc/Index/` — `IndexManager.swift` owns the SQLite database; `IndexSchema.swift` defines the schema; `OCRService.swift` handles Vision OCR
- One SQLite file per session: `~/.tmrc/index/<session>.sqlite`
- `RebuildIndexCommand.swift` re-runs OCR over existing segments

### 3. CLI
- `Sources/tmrc/CLI/` — one file per subcommand (`record`, `ask`, `export`, `status`, `install`, `uninstall`, `wipe`, `rebuild-index`)
- `Sources/tmrc/Recall/` — `AskEngine.swift` keyword search + citation output; `TimeRangeParser.swift` parses `--from`/`--to` expressions
- `Sources/tmrc/Export/` — `ExportEngine.swift` stitches segments into MP4 or GIF via AVFoundation/ffmpeg

### Support
- `Sources/tmrc/Config/` — `ConfigLoader.swift` reads `config.yaml` (YAML via Yams); `TMRCConfig.swift` is the config model
- `Sources/tmrc/Storage/` — `StorageManager.swift` handles directory layout; `RetentionManager.swift` enforces max-age/max-disk ring-buffer eviction
- `Sources/tmrc/Support/` — `Logger.swift` (single file, 7-day rotation), `Notifier.swift` (macOS toast notifications), `TMRCVersion.swift`
- `Sources/tmrc/Operations/` — `Installer.swift` manages LaunchAgent plist install/uninstall

### Storage layout (`~/.tmrc/` by default)
```
~/.tmrc/
├── tmrc.pid
├── tmrc.log
├── index/<session>.sqlite
└── segments/...
```

Config for dev: `config.yaml` in project root. Installed config: `~/.config/tmrc/config.yaml`.

## Key dependencies
- `swift-argument-parser` — CLI command structure
- `Yams` — YAML config parsing
- `GRDB` — SQLite ORM for the index
- `swift-testing` — test framework (used in test targets)

## Tests
Test files in `Tests/tmrcTests/` cover: `AskTests`, `ConfigTests`, `ExportTests`, `IndexTests`, `SegmenterTests`, `StorageTests`, `TimeRangeParserTests`.
