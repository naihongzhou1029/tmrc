import Foundation
import Vision
import CoreVideo
import CoreGraphics

/// Runs Vision OCR on a single frame (CVPixelBuffer or CGImage). Used for per-segment summary indexing.
public struct OCRService {
    public let recognitionLanguages: [String]

    public init(recognitionLanguages: [String] = ["en-US", "zh-Hant", "zh-Hans"]) {
        self.recognitionLanguages = recognitionLanguages
    }

    /// Extract text from a pixel buffer (e.g. middle frame of a segment). Returns nil on failure or empty.
    public func recognize(pixelBuffer: CVPixelBuffer) -> String? {
        let request = makeRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        return extractText(from: request)
    }

    /// Extract text from a CGImage (e.g. frame from segment file for rebuild-index).
    public func recognize(cgImage: CGImage) -> String? {
        let request = makeRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        return extractText(from: request)
    }

    private func makeRequest() -> VNRecognizeTextRequest {
        let request = VNRecognizeTextRequest()
        request.recognitionLanguages = recognitionLanguages
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        return request
    }

    private func extractText(from request: VNRecognizeTextRequest) -> String? {
        guard let observations = request.results as? [VNRecognizedTextObservation] else {
            return nil
        }
        let lines = observations.compactMap { $0.topCandidates(1).first?.string }
        let text = lines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
