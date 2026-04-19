import Testing
import Foundation
import AppKit
@testable import tmrc

/// Integration test: take a screenshot, OCR a keyword, record the screen for a few seconds,
/// then verify that `SearchEngine` finds segments matching the keyword and `ExportEngine` can
/// export them to an MP4. Requires screen-capture permission.
struct QueryTests {

    // MARK: - Helpers

    /// Run an external process and return stdout. Throws on non-zero exit.
    private func shell(_ args: [String], env: [String: String]? = nil) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = args
        if let env = env {
            var merged = ProcessInfo.processInfo.environment
            for (k, v) in env { merged[k] = v }
            process.environment = merged
        }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if process.terminationStatus != 0 {
            throw SanityError.processError(args.first ?? "", process.terminationStatus)
        }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// Locate the tmrc binary built alongside the test bundle.
    private func tmrcBinaryPath() -> String {
        // During `swift test`, the build products share the same directory.
        let testBundle = Bundle(for: _Anchor.self).bundlePath
        let dir = (testBundle as NSString).deletingLastPathComponent
        let candidate = (dir as NSString).appendingPathComponent("tmrc")
        if FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
        // Fallback: project-root symlink
        let projectRoot = ((#filePath as NSString)
            .deletingLastPathComponent as NSString)  // SanityQueryTests.swift -> tmrcTests/
            .deletingLastPathComponent               // tmrcTests/ -> Tests/
        let root = (projectRoot as NSString).deletingLastPathComponent  // Tests/ -> project root
        let symlink = (root as NSString).appendingPathComponent("tmrc")
        return (symlink as NSString).resolvingSymlinksInPath
    }

    /// Take a silent screenshot and return the path.
    private func takeScreenshot(to path: String) throws {
        _ = try shell(["screencapture", "-x", path])
        guard FileManager.default.fileExists(atPath: path) else {
            throw SanityError.screenshotFailed
        }
    }

    /// OCR a screenshot and return the best keyword (longest ASCII-letter word >= 4 chars).
    private func extractKeyword(from imagePath: String) throws -> String {
        guard let image = NSImage(contentsOfFile: imagePath),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw SanityError.imageLoadFailed(imagePath)
        }
        let ocr = OCRService(recognitionLanguages: ["en-US"])
        guard let text = ocr.recognize(cgImage: cgImage) else {
            throw SanityError.ocrEmpty
        }
        let words = text
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { $0.count >= 4 && $0.allSatisfy(\.isLetter) && $0.allSatisfy(\.isASCII) }
        guard let best = words.max(by: { $0.count < $1.count }) else {
            throw SanityError.noKeyword
        }
        return best
    }

    // MARK: - Test

    @Test("Sanity: screenshot keyword is found by search and exported by export")
    func queryFindsScreenKeyword() throws {
        let tmp = FileManager.default.temporaryDirectory.path + "/tmrc-sanity-\(UUID().uuidString)"
        let storageRoot = (tmp as NSString).appendingPathComponent("storage")
        try FileManager.default.createDirectory(atPath: storageRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tmp) }

        // Write isolated config
        let configPath = (tmp as NSString).appendingPathComponent("config.yaml")
        try "storage_root: \(storageRoot)\nsession: sanity\n"
            .write(toFile: configPath, atomically: true, encoding: .utf8)

        // 1. Screenshot + OCR
        let screenshotPath = (tmp as NSString).appendingPathComponent("screenshot.png")
        try takeScreenshot(to: screenshotPath)
        let keyword = try extractKeyword(from: screenshotPath)

        // 2. Record for 3 seconds
        let bin = tmrcBinaryPath()
        let env = ["TMRC_CONFIG_PATH": configPath]
        _ = try shell([bin, "start", "--session", "sanity"], env: env)
        Thread.sleep(forTimeInterval: 3)
        _ = try? shell([bin, "stop"], env: env)
        // Brief pause for segment flush + indexing
        Thread.sleep(forTimeInterval: 1)

        // 3. Search — verify keyword is found
        let storage = StorageManager(storageRoot: storageRoot)
        let indexManager = IndexManager(dbPath: storage.indexPath(session: "sanity"))
        let searchEngine = SearchEngine(indexManager: indexManager, session: "sanity", defaultRange: "5m")
        let (answer, segments) = try searchEngine.search(query: keyword, since: "5m ago", until: "now")
        #expect(!segments.isEmpty, "Expected segments matching \"\(keyword)\", got: \(answer)")

        // 4. Export — verify MP4 is produced
        let exportPath = (tmp as NSString).appendingPathComponent("export.mp4")
        let exportEngine = ExportEngine(storage: storage, indexManager: indexManager, session: "sanity")
        let from = Date().addingTimeInterval(-300)
        let to = Date()
        try exportEngine.export(from: from, to: to, query: keyword, outputPath: exportPath, format: "mp4")
        let attrs = try FileManager.default.attributesOfItem(atPath: exportPath)
        let size = (attrs[.size] as? Int) ?? 0
        #expect(size > 0, "Exported MP4 should be non-empty")
    }
}

// Anchor class for Bundle resolution in test context.
private final class _Anchor: NSObject {}

private enum SanityError: LocalizedError {
    case processError(String, Int32)
    case screenshotFailed
    case imageLoadFailed(String)
    case ocrEmpty
    case noKeyword

    var errorDescription: String? {
        switch self {
        case .processError(let cmd, let code): return "\(cmd) exited with status \(code)"
        case .screenshotFailed: return "screencapture did not produce a file"
        case .imageLoadFailed(let p): return "Cannot load image: \(p)"
        case .ocrEmpty: return "OCR returned no text from screenshot"
        case .noKeyword: return "No usable keyword (>=4 ASCII letters) found in OCR text"
        }
    }
}
