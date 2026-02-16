import Foundation

/// Simple file logger for tmrc. Writes to `storage_root/tmrc.log` with
/// version, timestamp, PID and log level. Uses a serial queue for writes.
public enum LogLevel: String {
    case debug
    case info
    case warn
    case error
}

public final class Logger {
    public static let shared = Logger()

    private let queue = DispatchQueue(label: "tmrc.logger.queue")
    private var logFileURL: URL?
    private var debugEnabled: Bool = false

    private static let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private init() {}

    /// Configure logger with storage and debug flag. Safe to call multiple times;
    /// last configuration wins.
    public func configure(storage: StorageManager, debugEnabled: Bool) {
        self.debugEnabled = debugEnabled || (ProcessInfo.processInfo.environment["TMRC_DEBUG"] == "1")
        let url = URL(fileURLWithPath: storage.logFilePath)
        logFileURL = url
        prepareLogFile(at: url)
    }

    /// Write one log line. If logger has not been configured, this is a no-op.
    public func log(_ message: String, level: LogLevel = .info, category: String? = nil) {
        guard let url = logFileURL else { return }
        if level == .debug && !debugEnabled { return }

        let timestamp = Logger.dateFormatter.string(from: Date())
        let pid = ProcessInfo.processInfo.processIdentifier
        let levelLabel = level.rawValue.uppercased()
        let categoryPart = category.map { "[\($0)] " } ?? ""
        let line = "\(timestamp) [\(TMRCVersion.current)] [pid:\(pid)] [\(levelLabel)] \(categoryPart)\(message)\n"

        let data = Data(line.utf8)
        queue.async {
            do {
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } catch {
                // Swallow logging errors; logger should never crash the app.
            }
        }
    }

    // MARK: - Private helpers

    /// Ensure directory exists, apply simple 7-day rotation, and create file if missing.
    private func prepareLogFile(at url: URL) {
        let fm = FileManager.default
        let dirURL = url.deletingLastPathComponent()

        // Ensure directory exists.
        if !fm.fileExists(atPath: dirURL.path) {
            try? fm.createDirectory(at: dirURL, withIntermediateDirectories: true)
        }

        // Simple time-based rotation: if file exists and is older than 7 days,
        // delete it and start fresh.
        if fm.fileExists(atPath: url.path) {
            if let attrs = try? fm.attributesOfItem(atPath: url.path),
               let mtime = attrs[.modificationDate] as? Date {
                if let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()),
                   mtime < cutoff {
                    try? fm.removeItem(at: url)
                }
            }
        }

        // Ensure file exists.
        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: nil)
        }
    }
}

