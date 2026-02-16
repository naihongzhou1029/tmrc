import Foundation
import ScreenCaptureKit
import CoreMedia
import CoreVideo
import CoreGraphics
import Darwin

/// Delivers the latest captured frame (and timing) for polling. Thread-safe.
public final class ScreenCaptureService: NSObject, SCStreamOutput {
    public struct LatestFrame {
        public let pixelBuffer: CVPixelBuffer
        public let presentationTime: CMTime
        public let wallTime: Date
        public let monotonicTime: Int64
    }

    private let sampleInterval: TimeInterval
    private let displayOption: DisplayOption
    private let queue = DispatchQueue(label: "tmrc.capture.queue")
    private var stream: SCStream?
    private var content: SCShareableContent?
    private var latest: (CVPixelBuffer, CMTime, Date, UInt64)?
    private var latestLock = NSLock()
    private var hasPermission: Bool = false

    public init(sampleInterval: TimeInterval, displayOption: DisplayOption) {
        self.sampleInterval = sampleInterval
        self.displayOption = displayOption
        super.init()
    }

    /// Fetch shareable content and start capture. Call once; completes asynchronously.
    public func start(completion: @escaping (Error?) -> Void) {
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true, completionHandler: { [weak self] (shareableContent: SCShareableContent?, error: Error?) in
            guard let self = self else { return }
            if let error = error {
                completion(error)
                return
            }
            guard let content = shareableContent else {
                completion(CaptureError.noDisplay)
                return
            }
            self.content = content
            self.hasPermission = true
            do {
                try self.startStream(with: content)
                self.stream?.startCapture(completionHandler: { err in
                    completion(err)
                })
            } catch {
                completion(error)
            }
        })
    }

    /// Returns the most recent frame and clears it so the next poll gets the next frame. Thread-safe.
    public func consumeLatestFrame() -> LatestFrame? {
        latestLock.lock()
        defer { latestLock.unlock() }
        guard let tuple = latest else { return nil }
        latest = nil
        let copy = copyPixelBuffer(tuple.0)
        return copy.map { LatestFrame(pixelBuffer: $0, presentationTime: tuple.1, wallTime: tuple.2, monotonicTime: Int64(bitPattern: tuple.3)) }
    }

    public func stop() {
        queue.async { [weak self] in
            self?.stream?.stopCapture()
            self?.stream = nil
        }
    }

    // MARK: - SCStreamOutput

    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let wall = Date()
        let mono = mach_continuous_time()
        guard let copy = copyPixelBuffer(imageBuffer) else { return }
        latestLock.lock()
        latest = (copy, pts, wall, mono)
        latestLock.unlock()
    }

    // MARK: - Private

    private func startStream(with content: SCShareableContent) throws {
        let display: SCDisplay
        switch displayOption {
        case .main:
            guard let main = content.displays.first(where: { $0.frame.contains(CGPoint(x: 0, y: 0)) }) ?? content.displays.first else {
                throw CaptureError.noDisplay
            }
            display = main
        case .combined:
            guard let main = content.displays.first else { throw CaptureError.noDisplay }
            display = main
        }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.minimumFrameInterval = CMTimeMakeWithSeconds(sampleInterval, preferredTimescale: 600)
        config.width = display.width
        config.height = display.height
        config.pixelFormat = kCVPixelFormatType_32BGRA
        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        do {
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        } catch {
            throw error
        }
        self.stream = stream
    }

    private func copyPixelBuffer(_ source: CVPixelBuffer) -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(source)
        let height = CVPixelBufferGetHeight(source)
        var copy: CVPixelBuffer?
        let attrs = [kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue!, kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue!] as CFDictionary
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height, CVPixelBufferGetPixelFormatType(source), attrs, &copy) == kCVReturnSuccess,
              let dest = copy else { return nil }
        CVPixelBufferLockBaseAddress(source, .readOnly)
        CVPixelBufferLockBaseAddress(dest, [])
        defer {
            CVPixelBufferUnlockBaseAddress(source, .readOnly)
            CVPixelBufferUnlockBaseAddress(dest, [])
        }
        let srcBase = CVPixelBufferGetBaseAddress(source)!
        let dstBase = CVPixelBufferGetBaseAddress(dest)!
        let bytesPerRow = CVPixelBufferGetBytesPerRow(source)
        let heightCount = CVPixelBufferGetHeight(source)
        memcpy(dstBase, srcBase, bytesPerRow * heightCount)
        return dest
    }
}

public enum CaptureError: LocalizedError {
    case noDisplay

    public var errorDescription: String? {
        switch self {
        case .noDisplay: return "No display available for capture."
        }
    }
}
