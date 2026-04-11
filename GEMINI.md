# Time Machine Recall Commander (tmrc) - Project Context

`tmrc` is a command-line tool for Windows that records your screen, indexes the content using OCR, and allows you to "recall" past activity through natural language queries or video/GIF exports. It is designed to be a local-first, CLI-only alternative to tools like Rewind.

## Project Overview

- **Core Technology:** .NET 8 / C#
- **Platform:** Windows (CLI + Background Daemon)
- **Primary Dependencies:**
  - **FFmpeg:** Used for MP4 segment encoding, stitching, and video export.
  - **Tesseract:** Used for OCR indexing of captured segments.
  - **SQLite:** Used for storing the segment index (`ocr_text`, `stt_text`, metadata).
- **Key Components:**
  - **Tmrc.Cli:** The main entry point for user commands (`record`, `ask`, `export`, etc.).
  - **Tmrc.Core:** Shared logic for configuration, storage, indexing, and recall.
  - **test_suite/Tmrc.Tests:** Comprehensive xUnit test suite.

## Architecture

1. **Background Daemon:** Started via `tmrc record`. It captures the screen (GDI BitBlt), segments recordings based on event activity, and runs the indexing pipeline (OCR via Tesseract).
2. **Indexing Pipeline:** Processes closed MP4 segments to extract text and updates the SQLite index.
3. **Recall (Ask/Export):**
   - `ask`: Keyword search over the OCR index to answer natural language questions.
   - `export`: Stitches segments into MP4/GIF for a given time range or query match.

## Development Workflow

### Safe Build & Run Workflow
Before executing any build or run command (e.g., `dotnet build`, `dotnet run`, or `./devops.ps1 build`), you MUST follow this sequence:
1. **Check Daemon Status**: `./devops.ps1 status`
2. **Stop the Daemon**: If `Recording: yes`, run `./devops.ps1 stop`.
3. **Verify Termination**: Ensure file locks are released and `tmrc.pid` is deleted.
4. **Proceed with Task**: Only proceed with the build or run once the daemon is stopped.

### Core Commands


| Command | Description |
| :--- | :--- |
| `./devops.ps1 setup` | Validates environment and installs missing prerequisites (.NET 8, FFmpeg, Tesseract). |
| `./devops.ps1 build` | Builds the `Tmrc.sln` solution. |
| `./devops.ps1 test` | Runs the xUnit test suite (requires a prior build). |
| `./devops.ps1 lint` | Runs `dotnet-format` on the solution. |
| `./devops.ps1 record` | Starts/stops the recording daemon. |
| `./devops.ps1 status` | Displays recording status, storage usage, and configuration. |
| `./devops.ps1 wipe` | Clears all recording segments and the index. |
| `./devops.ps1 reindex` | Re-runs OCR on existing segments (supports `--force`). |

### Key Files & Locations

- **Solution:** `src/Tmrc.sln`
- **Default Storage Root:** `%USERPROFILE%\.tmrc\`
- **Configuration:** `config.ini` in the project root (default template).
- **Logs:** `tmrc.log` in the storage root.
- **Index:** `index/<session>.sqlite` in the storage root.
- **Segments:** `segments/` directory in the storage root.
- **Specifications:** `specs/spec.md` (detailed architecture) and `specs/test.md` (test plan).

## Development Conventions

- **Code Style:** Adhere to standard C#/.NET 8 conventions. Use `dotnet-format` via `./devops.ps1 lint`.
- **Testing:** New features or bug fixes must be accompanied by tests in `src/test_suite/Tmrc.Tests`.
- **Logging:** Use the internal `Logger` class. Debug information can be enabled via `tmrc --debug` or `TMRC_DEBUG=1`.
- **Dependencies:** Always check if FFmpeg and Tesseract are on the `PATH` before performing recording or indexing operations.

## Troubleshooting

- **No OCR Results:** Ensure Tesseract is installed and available in the `PATH`. Use `./devops.ps1 setup` to verify.
- **Export Fails:** Ensure FFmpeg is installed. Video export requires stitching segments, which is handled by FFmpeg.
- **Daemon Issues:** Check `tmrc.log` and ensure only one instance is running (check `tmrc.pid`).
