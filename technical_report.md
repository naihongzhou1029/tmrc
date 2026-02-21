# Technical Report: AI-Driven Development of Time Machine Recall Commander (tmrc)

**Date:** February 20, 2026
**Target Audience:** Senior Software Engineers, Architects
**Topic:** The development journey, architectural decisions, and AI-assisted workflow behind `tmrc` (Time Machine Recall Commander).

---

## 1. Concept & Inception
The project began with a clear, concise vision: a local-first, CLI-only macOS tool to record screen activity, index it, and allow users to "recall" the past via text queries or video/GIF exports. 

We established the core constraints early on:
- **Platform:** macOS (Apple Silicon).
- **Core Tech:** Swift, utilizing native APIs (`ScreenCaptureKit`, `AVFoundation`, `Vision`).
- **Interface:** Strictly CLI, no GUI.

**First Artifact:** We documented these constraints, high-level architecture (Daemon + Indexing Pipeline + CLI), and goals in an initial `README.md`. This served as the foundational context for the AI.

## 2. Specification & Implementation Planning
Rather than jumping straight into code, the AI was tasked with expanding the `README.md` into a thorough, rigorous architecture specification.

**Artifact:** `specs/spec.md`
This document resolved ambiguous edge cases and defined 10 distinct architectural pillars, including:
- **Recording:** Event-based chunking (flushing segments on idle frames) rather than fixed-duration chunks to optimize storage.
- **Storage:** Ring-buffer retention policies (max age / max disk).
- **Indexing:** Asynchronous OCR processing using Apple's `Vision` framework, storing metadata in a per-session SQLite database.
- **Process Model:** A two-process architecture where the CLI communicates with a background daemon (tracked via PID file).

This spec shifted the project from a rough idea to a highly actionable blueprint.

## 3. Test-Driven AI Development
To close the development iteration loop and ensure the AI could reliably implement the system without drifting from requirements, we generated a comprehensive test matrix.

**Artifact:** `specs/test.md`
A 95-item test plan was created covering:
- Unit behaviors (config parsing, segment boundaries).
- Integration flows (SQLite schema setup, indexing failures).
- Operational edge cases (SIGTERM handling, `ScreenCaptureKit` stream errors, revoked permissions mid-session).

This matrix functioned as the "definition of done" for the upcoming autonomous implementation phase.

## 4. The Autonomous "Long Run"
With the `README.md`, specs, and test plan in place, the AI was prompted to execute a long, autonomous development run. Progress was continuously tracked and reconciled against `specs/building_progress.md`.

**Key Technical Milestones Achieved:**
1. **Daemon & Capture:** Implemented `ScreenCaptureService` using `ScreenCaptureKit` and an `EventSegmenter` to write H.264 MP4 segments via `AVAssetWriter`.
2. **Storage Management:** Built a robust `RetentionManager` that evaluates ring-buffer constraints on every segment flush.
3. **Indexing Pipeline:** Integrated `VNRecognizeTextRequest` for per-segment OCR, pushing results to a localized SQLite index.
4. **Recall Engine:** Implemented the `ask` (keyword search and templated response) and `export` (stitching MP4s, generating GIFs, resolving time queries) pipelines.

The heavy lifting of scaffolding the application, bridging C/Objective-C APIs with modern Swift, and wiring the CLI parser was handled autonomously based on the predefined specs.

## 5. Refinements & 1st macOS Release
Following the "long run," we achieved a fully functional v1 prototype. The final phase involved targeted manual tweaks, debugging, and UX tuning to hit release quality:

- **Resilience:** Implemented daemon auto-restarts for internal `ScreenCaptureKit` stream errors (`SCStreamErrorDomain`). Added robust crash recovery to prune incomplete segment files on startup.
- **Export Quality:** Switched to pass-through export for H.264 to prevent blurring and resolution loss during segment stitching.
- **System Feedback:** Since `tmrc` is CLI-only, we routed critical asynchronous events (e.g., storage full, OCR index failure, revoked macOS permissions) to native macOS Toast notifications.
- **CLI UX:** Refined status outputs, converting raw bytes to GB and formatting time intervals into human-readable `DD:HH:MM:SS`.

## Conclusion
The development of `tmrc` demonstrates a highly effective pattern for AI-assisted software engineering:
1. **Human:** Define the concept and constraints (`README.md`).
2. **AI:** Expand into thorough specifications (`spec.md`).
3. **AI:** Generate the test matrix to bound the implementation (`test.md`).
4. **AI:** Execute the bulk of implementation autonomously.
5. **Human + AI:** Refine, debug, and tune edge cases.

By front-loading the architecture and testing requirements, the AI was able to autonomously deliver a complex, multi-process macOS application utilizing low-level native frameworks with minimal hallucination or architectural drift.