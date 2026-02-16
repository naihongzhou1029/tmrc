import Foundation

/// Export time range or query to MP4/GIF. Stub: fails with clear message when segments missing or export not implemented.
public struct ExportEngine {
    public let storage: StorageManager
    public let indexManager: IndexManager
    public let session: String

    public init(storage: StorageManager, indexManager: IndexManager, session: String) {
        self.storage = storage
        self.indexManager = indexManager
        self.session = session
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
        // Full implementation would resolve segments, stitch, encode. For now:
        throw ExportError.notImplemented("Export (stitch/encode) is not yet implemented. Use tmrc ask for citations.")
    }
}

public enum ExportError: LocalizedError {
    case missingOutputPath
    case noSegments(String)
    case notImplemented(String)

    public var errorDescription: String? {
        switch self {
        case .missingOutputPath: return "Output path (-o) is required."
        case .noSegments(let msg): return msg
        case .notImplemented(let msg): return msg
        }
    }
}
