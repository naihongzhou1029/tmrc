import Foundation

/// Ring-buffer retention: evict oldest segments when max age or max disk is exceeded.
public struct RetentionManager {
    public let maxAgeDays: Int
    public let maxDiskBytes: Int64
    private let fileManager = FileManager.default

    public init(maxAgeDays: Int = 7, maxDiskBytes: Int64 = 50 * 1024 * 1024 * 1024) {
        self.maxAgeDays = maxAgeDays
        self.maxDiskBytes = maxDiskBytes
    }

    /// List segment paths with modification date, sorted oldest first.
    public func listSegmentsOldestFirst(segmentsDirectory: String) throws -> [(path: String, date: Date)] {
        guard fileManager.fileExists(atPath: segmentsDirectory) else { return [] }
        let contents = try fileManager.contentsOfDirectory(atPath: segmentsDirectory)
        var items: [(path: String, date: Date)] = []
        for name in contents where name.hasSuffix(".mp4") || name.hasSuffix(".mov") {
            let path = (segmentsDirectory as NSString).appendingPathComponent(name)
            if let attrs = try? fileManager.attributesOfItem(atPath: path),
               let date = attrs[.modificationDate] as? Date {
                items.append((path, date))
            }
        }
        items.sort { $0.date < $1.date }
        return items
    }

    /// Evict segments that are older than maxAgeDays or that push total size over maxDiskBytes.
    /// Deletes oldest first. Returns number of deleted files.
    public func evictIfNeeded(segmentsDirectory: String) throws -> Int {
        let list = try listSegmentsOldestFirst(segmentsDirectory: segmentsDirectory)
        let cutoff = Calendar.current.date(byAdding: .day, value: -maxAgeDays, to: Date()) ?? Date()
        var totalBytes: Int64 = 0
        for (path, _) in list {
            if let attrs = try? fileManager.attributesOfItem(atPath: path),
               let size = attrs[.size] as? Int64 {
                totalBytes += size
            }
        }
        var deleted = 0
        for (path, date) in list {
            let size: Int64 = (try? fileManager.attributesOfItem(atPath: path)).flatMap { $0[.size] as? Int64 } ?? 0
            if date < cutoff {
                try? fileManager.removeItem(atPath: path)
                deleted += 1
                totalBytes -= size
                continue
            }
            if totalBytes > maxDiskBytes {
                try? fileManager.removeItem(atPath: path)
                deleted += 1
                totalBytes -= size
            } else {
                break
            }
        }
        return deleted
    }
}
