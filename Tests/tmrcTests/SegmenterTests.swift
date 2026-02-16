import Testing
import Foundation
import CoreVideo
import CoreMedia
@testable import tmrc

struct SegmenterTests {

    @Test("Segment boundaries - one event then idle frame flushes")
    func segmentBoundaryOneEvent() throws {
        let segmenter = EventSegmenter()
        let buf1 = makePixelBuffer(width: 64, height: 64, fill: 0xFF0000)
        let buf2 = makePixelBuffer(width: 64, height: 64, fill: 0xFF0000)
        let wall = Date()
        let mono: Int64 = 1000
        let pts = CMTime(value: 0, timescale: 600)
        let d1 = segmenter.pushFrame(pixelBuffer: buf1, presentationTime: pts, wallTime: wall, monotonicTime: mono)
        if case .appended = d1 { } else { Issue.record("Expected appended, got \(d1)"); return }
        let d2 = segmenter.pushFrame(pixelBuffer: buf2, presentationTime: CMTime(value: 1, timescale: 600), wallTime: wall.addingTimeInterval(0.1), monotonicTime: mono + 1)
        if case .flush(_, _, _, _, _, let frames) = d2 {
            #expect(frames.count >= 1)
        } else {
            Issue.record("Expected flush, got \(d2)")
        }
    }

    @Test("Segment boundaries - burst then idle flushes one segment")
    func segmentBoundaryBurst() throws {
        let segmenter = EventSegmenter()
        let wall = Date()
        let mono: Int64 = 1000
        var pts = CMTime(value: 0, timescale: 600)
        for i in 0..<31 {
            let buf = makePixelBuffer(width: 64, height: 64, fill: UInt32(0xFF0000 + i))
            let d = segmenter.pushFrame(pixelBuffer: buf, presentationTime: pts, wallTime: wall.addingTimeInterval(Double(i) * 0.0322), monotonicTime: mono + Int64(i))
            if case .flush(_, _, _, _, _, let frames) = d {
                #expect(frames.count >= 1)
                return
            }
            pts = CMTime(value: Int64(i + 1), timescale: 600)
        }
        let idle = makePixelBuffer(width: 64, height: 64, fill: UInt32(0xFF0000 + 30))
        let d = segmenter.pushFrame(pixelBuffer: idle, presentationTime: pts, wallTime: wall.addingTimeInterval(1), monotonicTime: mono + 31)
        if case .flush(_, _, _, _, _, let frames) = d {
            #expect(frames.count >= 1)
        } else {
            Issue.record("Expected flush after idle, got \(d)")
        }
    }

    private func makePixelBuffer(width: Int32, height: Int32, fill: UInt32) -> CVPixelBuffer {
        var buf: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, Int(width), Int(height), kCVPixelFormatType_32BGRA, nil, &buf)
        guard let b = buf else { fatalError("CVPixelBufferCreate failed") }
        CVPixelBufferLockBaseAddress(b, [])
        defer { CVPixelBufferUnlockBaseAddress(b, []) }
        let ptr = CVPixelBufferGetBaseAddress(b)!.assumingMemoryBound(to: UInt32.self)
        let count = Int(width * height)
        for i in 0..<count { ptr[i] = fill }
        return b
    }
}
