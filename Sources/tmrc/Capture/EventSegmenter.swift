import Foundation
import CoreMedia
import CoreVideo

/// Event-based segment boundary: flush when the next frame has no significant change from previous.
/// One event yields at least one sample-interval clip; segment is flushed when next frame is "idle".
public enum FlushDecision {
    case noOp
    case appended
    case flush(segmentId: String, startTime: Date, endTime: Date, monotonicStart: Int64, monotonicEnd: Int64, frames: [(pixelBuffer: CVPixelBuffer, presentationTime: CMTime)])
}

public final class EventSegmenter {
    /// Fraction of sampled pixels that must differ to count as "event". Tuned to avoid noise.
    private let changeThreshold: Double
    /// Number of samples per axis (total samples = sampleGrid * sampleGrid).
    private let sampleGrid: Int

    private var previousSamples: [UInt32]?
    private var segmentFrames: [(pixelBuffer: CVPixelBuffer, presentationTime: CMTime)] = []
    private var segmentStartWall: Date?
    private var segmentStartMonotonic: Int64 = 0
    private var lastAppendedMonotonic: Int64 = 0
    private var nextSegmentId: String { UUID().uuidString }

    public init(changeThreshold: Double = 0.02, sampleGrid: Int = 16) {
        self.changeThreshold = changeThreshold
        self.sampleGrid = sampleGrid
    }

    /// Call once per captured frame. Returns .flush when segment should be written (idle frame after activity).
    public func pushFrame(
        pixelBuffer: CVPixelBuffer,
        presentationTime: CMTime,
        wallTime: Date,
        monotonicTime: Int64
    ) -> FlushDecision {
        let samples = samplePixels(pixelBuffer)
        let hasEvent = hasSignificantChange(current: samples, previous: previousSamples)
        previousSamples = samples

        if hasEvent {
            if segmentFrames.isEmpty {
                segmentStartWall = wallTime
                segmentStartMonotonic = monotonicTime
            }
            lastAppendedMonotonic = monotonicTime
            segmentFrames.append((pixelBuffer, presentationTime))
            return .appended
        }

        if segmentFrames.isEmpty {
            return .noOp
        }

        let segmentId = nextSegmentId
        let startWall = segmentStartWall ?? wallTime
        let endWall = wallTime
        let startMono = segmentStartMonotonic
        let endMono = monotonicTime
        let frames = segmentFrames
        segmentFrames = []
        segmentStartWall = nil
        return .flush(segmentId: segmentId, startTime: startWall, endTime: endWall, monotonicStart: startMono, monotonicEnd: endMono, frames: frames)
    }

    /// Call on shutdown to flush any open segment.
    public func flushPending() -> FlushDecision? {
        guard !segmentFrames.isEmpty,
              let startWall = segmentStartWall else { return nil }
        let endWall = Date()
        let segmentId = nextSegmentId
        let frames = segmentFrames
        segmentFrames = []
        segmentStartWall = nil
        return .flush(segmentId: segmentId, startTime: startWall, endTime: endWall, monotonicStart: segmentStartMonotonic, monotonicEnd: lastAppendedMonotonic, frames: frames)
    }

    // MARK: - Change detection

    private func samplePixels(_ buffer: CVPixelBuffer) -> [UInt32] {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return [] }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        guard width >= sampleGrid, height >= sampleGrid else { return [] }

        var out: [UInt32] = []
        let stepX = max(1, width / sampleGrid)
        let stepY = max(1, height / sampleGrid)
        let ptr = base.assumingMemoryBound(to: UInt8.self)
        for y in stride(from: 0, to: height, by: stepY) {
            for x in stride(from: 0, to: width, by: stepX) {
                let offset = y * bytesPerRow + x * 4
                let b = UInt32(ptr[offset])
                let g = UInt32(ptr[offset + 1])
                let r = UInt32(ptr[offset + 2])
                out.append((r << 16) | (g << 8) | b)
            }
        }
        return out
    }

    private func hasSignificantChange(current: [UInt32], previous: [UInt32]?) -> Bool {
        guard let prev = previous, prev.count == current.count else { return true }
        let differing = zip(prev, current).filter { $0.0 != $0.1 }.count
        return Double(differing) / Double(current.count) >= changeThreshold
    }
}
