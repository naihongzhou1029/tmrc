import Foundation
import CoreGraphics
import CoreMedia
import CoreVideo

/// Daemon loop: ScreenCaptureKit → event segmenter → segment writer → index. Runs until SIGTERM/SIGINT.
struct DaemonRunner {
    let storage: StorageManager
    let session: String
    let config: TMRCConfig
    private let sampleInterval: TimeInterval

    init(storage: StorageManager, session: String, config: TMRCConfig) {
        self.storage = storage
        self.session = session
        self.config = config
        self.sampleInterval = config.sampleRateMs / 1000.0
    }

    func runUntilSignalled() {
        let capture = ScreenCaptureService(sampleInterval: sampleInterval, displayOption: config.display)
        let segmenter = EventSegmenter()
        let writer = SegmentWriter()
        var indexManager = IndexManager(dbPath: storage.indexPath(session: session))
        let retention = RetentionManager()

        capture.onStreamError = { DaemonEntry.signalReceived = true }
        let started = DispatchSemaphore(value: 0)
        var startError: Error?
        capture.start { err in
            startError = err
            started.signal()
        }
        started.wait()
        if let err = startError {
            Logger.shared.log("Capture start failed: \(err.localizedDescription)", level: .error, category: "daemon")
            return
        }
        defer { capture.stop() }

        let lowSpaceThreshold: Int64 = 100 * 1024 * 1024 // 100 MB
        while !DaemonEntry.signalReceived {
            if let free = storage.freeSpace(), free < lowSpaceThreshold {
                Logger.shared.log("Low disk space (\(free) bytes). Stopping.", level: .error, category: "daemon")
                Notifier.notify(title: "tmrc", body: "Low disk space. Recording saved and stopped.")
                DaemonEntry.signalReceived = true
                break
            }
            Thread.sleep(forTimeInterval: sampleInterval)
            guard let frame = capture.consumeLatestFrame() else { continue }
            let decision = segmenter.pushFrame(
                pixelBuffer: frame.pixelBuffer,
                presentationTime: frame.presentationTime,
                wallTime: frame.wallTime,
                monotonicTime: frame.monotonicTime
            )
            if case .flush(let segmentId, let startTime, let endTime, let monoStart, let monoEnd, let frames) = decision {
                writeSegmentAndIndex(
                    segmentId: segmentId,
                    startTime: startTime,
                    endTime: endTime,
                    monotonicStart: monoStart,
                    monotonicEnd: monoEnd,
                    frames: frames,
                    writer: writer,
                    indexManager: &indexManager,
                    retention: retention
                )
            }
        }

        if let pending = segmenter.flushPending(),
           case .flush(let segmentId, let startTime, let endTime, let monoStart, let monoEnd, let frames) = pending {
            writeSegmentAndIndex(
                segmentId: segmentId,
                startTime: startTime,
                endTime: endTime,
                monotonicStart: monoStart,
                monotonicEnd: monoEnd,
                frames: frames,
                writer: writer,
                indexManager: &indexManager,
                retention: retention
            )
        }
    }

    private func writeSegmentAndIndex(
        segmentId: String,
        startTime: Date,
        endTime: Date,
        monotonicStart: Int64,
        monotonicEnd: Int64,
        frames: [(pixelBuffer: CVPixelBuffer, presentationTime: CMTime)],
        writer: SegmentWriter,
        indexManager: inout IndexManager,
        retention: RetentionManager
    ) {
        let path = (storage.segmentsDirectory as NSString).appendingPathComponent("\(segmentId).mp4")
        do {
            try writer.writeSegment(segmentId: segmentId, frames: frames, outputPath: path)
            var segment = IndexSegment(
                id: segmentId,
                session: session,
                startTime: startTime,
                endTime: endTime,
                monotonicStart: monotonicStart,
                monotonicEnd: monotonicEnd,
                ocrText: nil,
                sttText: nil,
                filePath: path,
                status: "pending"
            )
            try indexManager.upsert(segment)

            let ocr = OCRService(recognitionLanguages: config.ocrRecognitionLanguages)
            let frameIndex = min(frames.count / 2, frames.count - 1)
            if frameIndex >= 0, let ocrText = ocr.recognize(pixelBuffer: frames[frameIndex].pixelBuffer) {
                segment.ocrText = ocrText
                segment.status = "indexed"
                try indexManager.upsert(segment)
            }

            Logger.shared.log("Segment written \(segmentId) (\(frames.count) frames)", level: .info, category: "daemon")
            _ = try retention.evictIfNeeded(segmentsDirectory: storage.segmentsDirectory)
        } catch {
            Logger.shared.log("Segment write/index failed: \(error.localizedDescription)", level: .error, category: "daemon")
        }
    }
}
