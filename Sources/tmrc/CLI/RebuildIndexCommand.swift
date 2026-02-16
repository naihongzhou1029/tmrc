import ArgumentParser
import Darwin
import Foundation
import AVFoundation
import CoreMedia
import CoreGraphics

public struct RebuildIndexCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "rebuild-index",
        abstract: "Rebuild the index from existing segment files (re-run OCR)."
    )

    @Option(name: .long, help: "Session name (default from config)")
    public var session: String?

    public init() {}

    public mutating func run() throws {
        if CommandLine.arguments.contains("--version") {
            print(TMRCVersion.current)
            Darwin.exit(0)
        }
        let configPath = ConfigLoader.resolveConfigPath(projectRoot: FileManager.default.currentDirectoryPath)
        let config: TMRCConfig
        if FileManager.default.fileExists(atPath: configPath) {
            config = try ConfigLoader.load(fromFile: configPath)
        } else {
            config = TMRCConfig.default()
        }
        let sessionName = session ?? config.session
        let storage = StorageManager(storageRoot: config.storageRoot)
        Logger.shared.configure(
            storage: storage,
            debugEnabled: CommandLine.arguments.contains("--debug")
        )

        var indexManager = IndexManager(dbPath: storage.indexPath(session: sessionName))
        try indexManager.connect()
        let segmentPaths = try storage.listSegmentFiles()
        let ocr = OCRService(recognitionLanguages: config.ocrRecognitionLanguages)
        var rebuilt = 0
        for path in segmentPaths {
            let filename = (path as NSString).lastPathComponent
            guard filename.hasSuffix(".mp4") else { continue }
            let segmentId = (filename as NSString).deletingPathExtension

            guard let cgImage = frameFromSegment(path: path) else {
                Logger.shared.log("Rebuild: could not read frame from \(path)", level: .warn, category: "cli")
                continue
            }
            let ocrText = ocr.recognize(cgImage: cgImage)

            var segment: IndexSegment
            if let existing = try indexManager.segment(id: segmentId, session: sessionName) {
                segment = existing
                segment.ocrText = ocrText
                segment.status = "indexed"
            } else {
                let (start, end, monoStart, monoEnd) = try metadataFromSegment(path: path)
                segment = IndexSegment(
                    id: segmentId,
                    session: sessionName,
                    startTime: start,
                    endTime: end,
                    monotonicStart: monoStart,
                    monotonicEnd: monoEnd,
                    ocrText: ocrText,
                    sttText: nil,
                    filePath: path,
                    status: "indexed"
                )
            }
            try indexManager.upsert(segment)
            rebuilt += 1
        }
        print("Rebuilt index for \(rebuilt) segment(s) (session: \(sessionName)).")
        Logger.shared.log("Rebuild-index completed (session=\(sessionName), count=\(rebuilt))", level: .info, category: "cli")
    }

    private func frameFromSegment(path: String) -> CGImage? {
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let duration = CMTimeGetSeconds(asset.duration)
        guard duration > 0 else { return nil }
        let time = CMTime(seconds: duration / 2, preferredTimescale: 600)
        return try? generator.copyCGImage(at: time, actualTime: nil)
    }

    private func metadataFromSegment(path: String) throws -> (Date, Date, Int64, Int64) {
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        let durationSec = CMTimeGetSeconds(asset.duration)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let mtime = attrs[.modificationDate] as? Date else {
            let now = Date()
            return (now, now.addingTimeInterval(max(1, durationSec)), 0, 1)
        }
        let start = mtime
        let end = mtime.addingTimeInterval(max(0.1, durationSec))
        let mono = Int64(mtime.timeIntervalSince1970 * 1_000_000_000)
        return (start, end, mono, mono + 1)
    }
}
