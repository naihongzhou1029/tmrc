import Foundation
import Darwin

/// Discovers daemon via PID file, stops it (SIGTERM), and manages pid/socket paths. Can start the daemon process.
public struct DaemonManager {
    public let storageManager: StorageManager
    private let fileManager = FileManager.default

    public init(storageManager: StorageManager) {
        self.storageManager = storageManager
    }

    /// Start the daemon (spawn subprocess). Fails if already running. Waits for PID file with timeout.
    public func start(session: String, configPath: String) throws {
        if isRunning() {
            throw DaemonError.alreadyRunning
        }
        let process = Process()
        let argv0 = CommandLine.arguments.first ?? "/usr/bin/env"
        let resolved = (argv0 as NSString).resolvingSymlinksInPath
        process.executableURL = URL(fileURLWithPath: FileManager.default.fileExists(atPath: resolved) ? resolved : argv0)
        process.arguments = ["--daemon", storageManager.storageRoot, session, configPath]
        process.standardInput = nil
        process.standardOutput = nil
        process.standardError = nil
        try process.run()
        for _ in 0..<50 {
            Thread.sleep(forTimeInterval: 0.1)
            if fileManager.fileExists(atPath: storageManager.pidFilePath) {
                return
            }
        }
        process.terminate()
        throw DaemonError.startTimeout
    }

    /// Whether a daemon process is currently running (PID file exists and process exists).
    public func isRunning() -> Bool {
        guard let pid = readPID() else { return false }
        return processExists(pid)
    }

    /// Read PID from tmrc.pid if present.
    public func readPID() -> Int32? {
        let path = storageManager.pidFilePath
        guard fileManager.fileExists(atPath: path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let pid = Int32(str) else {
            return nil
        }
        return pid
    }

    /// Stop daemon if running: send SIGTERM, wait briefly, remove pid/socket. No-op if not running.
    public func stopIfRunning() throws {
        guard let pid = readPID(), processExists(pid) else {
            removePidAndSocket()
            return
        }
        kill(pid, SIGTERM)
        for _ in 0..<30 {
            usleep(100_000)
            if !processExists(pid) { break }
        }
        removePidAndSocket()
    }

    private func processExists(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0
    }

    private func removePidAndSocket() {
        try? fileManager.removeItem(atPath: storageManager.pidFilePath)
        try? fileManager.removeItem(atPath: storageManager.socketPath)
    }
}

public enum DaemonError: LocalizedError {
    case alreadyRunning
    case startTimeout

    public var errorDescription: String? {
        switch self {
        case .alreadyRunning: return "Recording is already in progress."
        case .startTimeout: return "Daemon failed to start in time."
        }
    }
}
