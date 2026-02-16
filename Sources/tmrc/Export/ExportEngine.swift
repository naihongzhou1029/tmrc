import Foundation
import AVFoundation
import CoreMedia
import ImageIO
import UniformTypeIdentifiers

/// Export time range or query to MP4/GIF. Resolves segments, stitches, encodes; fails clearly on missing segments.
public struct ExportEngine {
    public let storage: StorageManager
    public let indexManager: IndexManager
    public let session: String
    public let quality: ExportQuality

    public init(storage: StorageManager, indexManager: IndexManager, session: String, quality: ExportQuality = .high) {
        self.storage = storage
        self.indexManager = indexManager
        self.session = session
        self.quality = quality
    }

    /// Export [from, to] or query-matched range to path. Returns path or throws.
    public func export(from: Date?, to: Date?, query: String?, outputPath: String, format: String) throws {
        guard !outputPath.isEmpty else {
            throw ExportError.missingOutputPath
        }
        var index = indexManager
        if try index.isEmpty(session: session) {
            throw ExportError.noSegments("No segments in index for session \"\(session)\". Record first.")
        }

        let (fromDate, toDate): (Date, Date)
        if let q = query, !q.isEmpty {
            let (start, end) = try resolveQueryRange(index: &index, query: q)
            fromDate = start
            toDate = end
        } else if let f = from, let t = to {
            fromDate = f
            toDate = t
        } else {
            throw ExportError.noSegments("Export requires --from and --to, or --query.")
        }

        let segments = try index.segments(from: fromDate, to: toDate, session: session)
        if segments.isEmpty {
            throw ExportError.noSegments("No segments in the given time range.")
        }

        // Prefer newer on overlap: sort by startTime then by endTime descending so newer (later-written) wins when trimming.
        let ordered = segments.sorted { a, b in
            if a.startTime != b.startTime { return a.startTime < b.startTime }
            return a.endTime > b.endTime
        }
        var uniqueByTime: [IndexSegment] = []
        var lastEnd: Date?
        for seg in ordered {
            if let last = lastEnd, seg.endTime <= last { continue }
            uniqueByTime.append(seg)
            lastEnd = seg.endTime
        }

        for seg in uniqueByTime {
            guard FileManager.default.fileExists(atPath: seg.filePath) else {
                throw ExportError.missingSegment(seg.id, path: seg.filePath)
            }
        }

        let fmt = format.lowercased()
        if fmt == "gif" {
            try exportGIF(segments: uniqueByTime, outputPath: outputPath)
        } else {
            try exportMP4(segments: uniqueByTime, outputPath: outputPath)
        }
    }

    private func resolveQueryRange(index: inout IndexManager, query: String) throws -> (Date, Date) {
        let parser = TimeRangeParser()
        let (from, to) = parser.parseDefaultRange("24h")
        let matches = try index.search(keyword: query, from: from, to: to, session: session)
        guard !matches.isEmpty else {
            throw ExportError.noSegments("No segments match query \"\(query)\" in the default range.")
        }
        let start = matches.map(\.startTime).min()!
        let end = matches.map(\.endTime).max()!
        return (start, end)
    }

    private func exportMP4(segments: [IndexSegment], outputPath: String) throws {
        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw ExportError.exportFailed("Could not create composition video track.")
        }

        var currentTime = CMTime.zero
        var naturalSize = CGSize.zero

        for seg in segments {
            let url = URL(fileURLWithPath: seg.filePath)
            let asset = AVURLAsset(url: url)
            guard let track = asset.tracks(withMediaType: .video).first else { continue }
            let range = CMTimeRange(start: .zero, duration: asset.duration)
            if naturalSize == .zero {
                naturalSize = track.naturalSize
            }
            try videoTrack.insertTimeRange(range, of: track, at: currentTime)
            currentTime = CMTimeAdd(currentTime, range.duration)
        }

        let outputURL = URL(fileURLWithPath: outputPath)
        if FileManager.default.fileExists(atPath: outputPath) {
            try FileManager.default.removeItem(at: outputURL)
        }

        let preset: String
        switch quality {
        case .low: preset = AVAssetExportPreset1280x720
        case .medium: preset = AVAssetExportPreset1920x1080
        case .high: preset = AVAssetExportPresetHighestQuality
        }

        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: preset
        ) else {
            throw ExportError.exportFailed("Could not create export session.")
        }
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4

        let semaphore = DispatchSemaphore(value: 0)
        var exportError: Error?
        exportSession.exportAsynchronously {
            exportError = exportSession.error
            semaphore.signal()
        }
        semaphore.wait()

        if let exportError = exportError {
            throw ExportError.exportFailed(exportError.localizedDescription)
        }
    }

    private func exportGIF(segments: [IndexSegment], outputPath: String) throws {
        var images: [(CGImage, Double)] = []
        let frameCount = 30
        for seg in segments {
            let url = URL(fileURLWithPath: seg.filePath)
            let asset = AVURLAsset(url: url)
            let duration = asset.duration.seconds
            guard duration > 0 else { continue }
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero

            let count = min(frameCount, Int(duration * 10))
            if count <= 0 { continue }
            for i in 0..<count {
                let t = Double(i) / Double(max(1, count)) * duration
                let cmTime = CMTime(seconds: t, preferredTimescale: 600)
                do {
                    let cgImage = try generator.copyCGImage(at: cmTime, actualTime: nil)
                    images.append((cgImage, t))
                } catch {
                    continue
                }
            }
        }
        guard !images.isEmpty else {
            throw ExportError.exportFailed("No frames could be extracted for GIF.")
        }

        let outputURL = URL(fileURLWithPath: outputPath)
        if FileManager.default.fileExists(atPath: outputPath) {
            try FileManager.default.removeItem(at: outputURL)
        }

        guard let dest = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            UTType.gif.identifier as CFString,
            images.count,
            nil
        ) else {
            throw ExportError.exportFailed("Could not create GIF destination.")
        }

        let frameDuration = 0.1
        let gifProps: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFLoopCount as String: 0
            ]
        ]
        CGImageDestinationSetProperties(dest, gifProps as CFDictionary)

        for (cgImage, _) in images {
            let frameProps: [String: Any] = [
                kCGImagePropertyGIFDictionary as String: [
                    kCGImagePropertyGIFDelayTime as String: frameDuration
                ]
            ]
            CGImageDestinationAddImage(dest, cgImage, frameProps as CFDictionary)
        }
        guard CGImageDestinationFinalize(dest) else {
            throw ExportError.exportFailed("Failed to finalize GIF.")
        }
    }
}

public enum ExportError: LocalizedError {
    case missingOutputPath
    case noSegments(String)
    case missingSegment(String, path: String)
    case exportFailed(String)
    case notImplemented(String)

    public var errorDescription: String? {
        switch self {
        case .missingOutputPath: return "Output path (-o) is required."
        case .noSegments(let msg): return msg
        case .missingSegment(let id, let path): return "Segment \(id) is missing or unreadable at \(path). Export failed."
        case .exportFailed(let msg): return "Export failed: \(msg)"
        case .notImplemented(let msg): return msg
        }
    }
}
