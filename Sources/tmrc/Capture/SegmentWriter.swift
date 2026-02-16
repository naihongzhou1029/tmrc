import Foundation
import AVFoundation
import CoreMedia
import CoreVideo

/// Writes a sequence of pixel buffers to an MP4 file using AVAssetWriter (H.264).
public final class SegmentWriter {
    private let fileType: AVFileType = .mp4

    public init() {}

    /// Writes frames to outputPath. Frames must have the same dimensions; first frame defines format.
    /// Uses wall-clock presentation times; segment duration = lastTime - firstTime.
    public func writeSegment(
        segmentId: String,
        frames: [(pixelBuffer: CVPixelBuffer, presentationTime: CMTime)],
        outputPath: String
    ) throws {
        guard let first = frames.first else { return }
        let width = CVPixelBufferGetWidth(first.pixelBuffer)
        let height = CVPixelBufferGetHeight(first.pixelBuffer)
        guard width > 0, height > 0 else {
            throw SegmentWriterError.invalidDimensions(width: width, height: height)
        }

        let url = URL(fileURLWithPath: outputPath)
        if FileManager.default.fileExists(atPath: outputPath) {
            try FileManager.default.removeItem(at: url)
        }

        let writer = try AVAssetWriter(outputURL: url, fileType: fileType)
        let sourceFormatDescription = try CMVideoFormatDescription(imageBuffer: first.pixelBuffer)
        let outputSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 8_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ] as [String: Any],
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: outputSettings, sourceFormatHint: sourceFormatDescription)
        input.expectsMediaDataInRealTime = false
        writer.add(input)

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            ]
        )

        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        // Use 30 fps timescale so each frame is 1/30 s; segment times are relative to start.
        let scale = CMTimeScale(30)
        for (idx, frame) in frames.enumerated() {
            while !input.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.005)
            }
            let pts = CMTime(value: CMTimeValue(idx), timescale: scale)
            if !adaptor.append(frame.pixelBuffer, withPresentationTime: pts) {
                throw SegmentWriterError.appendFailed(frameIndex: idx)
            }
        }

        input.markAsFinished()
        let endTime = CMTime(value: CMTimeValue(frames.count), timescale: scale)
        writer.endSession(atSourceTime: endTime)
        let semaphore = DispatchSemaphore(value: 0)
        var finishError: Error?
        writer.finishWriting {
            finishError = writer.error
            semaphore.signal()
        }
        semaphore.wait()
        if let finishError = finishError {
            throw SegmentWriterError.finishFailed(finishError)
        }
    }
}

public enum SegmentWriterError: LocalizedError {
    case invalidDimensions(width: Int, height: Int)
    case appendFailed(frameIndex: Int)
    case finishFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .invalidDimensions(let w, let h): return "Invalid frame dimensions: \(w)x\(h)"
        case .appendFailed(let i): return "Failed to append frame at index \(i)"
        case .finishFailed(let e): return "Failed to finish writing: \(e.localizedDescription)"
        }
    }
}
