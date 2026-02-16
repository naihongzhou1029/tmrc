import Foundation

/// Resolves storage root, creates dirs, and provides path helpers. Paths are deterministic (no binary-path dependency).
public struct StorageManager {
    public let storageRoot: String
    private let fileManager = FileManager.default

    public init(storageRoot: String) {
        self.storageRoot = (storageRoot as NSString).expandingTildeInPath
    }

    /// PID file path for daemon discovery.
    public var pidFilePath: String {
        (storageRoot as NSString).appendingPathComponent("tmrc.pid")
    }

    /// Unix socket path for CLI–daemon communication.
    public var socketPath: String {
        (storageRoot as NSString).appendingPathComponent("tmrc.sock")
    }

    /// Log file path (single file, 7-day rotation).
    public var logFilePath: String {
        (storageRoot as NSString).appendingPathComponent("tmrc.log")
    }

    /// Index directory.
    public var indexDirectory: String {
        (storageRoot as NSString).appendingPathComponent("index")
    }

    /// Index file path for a session.
    public func indexPath(session: String) -> String {
        (indexDirectory as NSString).appendingPathComponent("\(session).sqlite")
    }

    /// Segments directory (flat or date-based TBD; use flat for v1).
    public var segmentsDirectory: String {
        (storageRoot as NSString).appendingPathComponent("segments")
    }

    /// Create storage_root, index/, segments/ if missing. Does not create tmrc.pid (created when daemon starts).
    public func createLayoutIfNeeded() throws {
        try fileManager.createDirectory(atPath: storageRoot, withIntermediateDirectories: true, attributes: nil)
        try fileManager.createDirectory(atPath: indexDirectory, withIntermediateDirectories: true, attributes: nil)
        try fileManager.createDirectory(atPath: segmentsDirectory, withIntermediateDirectories: true, attributes: nil)
    }

    /// Check if storage root exists and is writable.
    public func ensureWritable() throws {
        guard fileManager.fileExists(atPath: storageRoot) else {
            throw StorageError.pathNotFound(storageRoot)
        }
        let testFile = (storageRoot as NSString).appendingPathComponent(".tmrc_write_test_\(UUID().uuidString)")
        defer { try? fileManager.removeItem(atPath: testFile) }
        guard fileManager.createFile(atPath: testFile, contents: nil) else {
            throw StorageError.notWritable(storageRoot)
        }
    }

    /// List segment file paths (for retention and usage). Returns absolute paths.
    public func listSegmentFiles() throws -> [String] {
        guard fileManager.fileExists(atPath: segmentsDirectory) else { return [] }
        let contents = try fileManager.contentsOfDirectory(atPath: segmentsDirectory)
        return contents
            .filter { $0.hasSuffix(".mp4") || $0.hasSuffix(".mov") }
            .map { (segmentsDirectory as NSString).appendingPathComponent($0) }
    }

    /// Total size in bytes of a path (file or directory).
    public func sizeOfItem(at path: String) throws -> Int64 {
        let attrs = try fileManager.attributesOfItem(atPath: path)
        guard let size = attrs[.size] as? Int64 else { return 0 }
        return size
    }

    /// Recursive size of directory.
    public func totalSize(of directory: String) throws -> Int64 {
        guard let enumerator = fileManager.enumerator(atPath: directory) else { return 0 }
        var total: Int64 = 0
        while let name = enumerator.nextObject() as? String {
            let path = (directory as NSString).appendingPathComponent(name)
            if let attrs = try? fileManager.attributesOfItem(atPath: path),
               let size = attrs[.size] as? Int64 {
                total += size
            }
        }
        return total
    }

    /// Disk usage for storage root (total bytes).
    public func diskUsage() throws -> Int64 {
        try totalSize(of: storageRoot)
    }

    /// Free space (bytes) on the volume containing storageRoot. Returns nil if unavailable.
    public func freeSpace() -> Int64? {
        guard let attrs = try? fileManager.attributesOfFileSystem(forPath: storageRoot),
              let free = attrs[.systemFreeSize] as? Int64 else { return nil }
        return free
    }
}

public enum StorageError: LocalizedError {
    case pathNotFound(String)
    case notWritable(String)

    public var errorDescription: String? {
        switch self {
        case .pathNotFound(let p): return "Storage path not found: \(p)"
        case .notWritable(let p): return "Storage path is not writable: \(p)"
        }
    }
}
