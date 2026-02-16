import Foundation
import Darwin

/// When running as daemon (tmrc --daemon), this runs the capture loop. Called from main after parsing.
public struct DaemonEntry {
    public static func runAsDaemon(storageRoot: String, session: String, configPath: String) throws -> Never {
        let storage = StorageManager(storageRoot: storageRoot)
        try storage.createLayoutIfNeeded()
        try storage.ensureWritable()

        // Configure logger early so all daemon activity is captured.
        Logger.shared.configure(
            storage: storage,
            debugEnabled: CommandLine.arguments.contains("--debug")
        )
        Logger.shared.log("Daemon starting (session=\(session), config=\(configPath))", level: .info, category: "daemon")

        let daemon = DaemonManager(storageManager: storage)
        if daemon.isRunning() {
            fputs("Another tmrc recorder is already running.\n", stderr)
            Logger.shared.log("Start aborted: another daemon is already running", level: .error, category: "daemon")
            Darwin.exit(1)
        }

        let pid = ProcessInfo.processInfo.processIdentifier
        try "\(pid)\n".write(toFile: storage.pidFilePath, atomically: true, encoding: .utf8)

        signal(SIGTERM) { _ in
            DaemonEntry.signalReceived = true
        }
        signal(SIGINT) { _ in
            DaemonEntry.signalReceived = true
        }

        defer {
            Logger.shared.log("Daemon shutting down (signalReceived=\(DaemonEntry.signalReceived))", level: .info, category: "daemon")
            try? FileManager.default.removeItem(atPath: storage.pidFilePath)
            try? FileManager.default.removeItem(atPath: storage.socketPath)
            Darwin.exit(0)
        }

        let config: TMRCConfig
        if FileManager.default.fileExists(atPath: configPath) {
            config = try ConfigLoader.load(fromFile: configPath)
        } else {
            config = TMRCConfig.default()
        }

        // Crash recovery: remove incomplete segment files (0 or very small) from previous run.
        try removeIncompleteSegments(storage: storage)

        let runner = DaemonRunner(storage: storage, session: session, config: config)
        Logger.shared.log("Daemon entering main loop (sampleInterval=\(config.sampleRateMs)ms)", level: .info, category: "daemon")
        runner.runUntilSignalled()
        Darwin.exit(0)
    }

    static var signalReceived = false

    private static func removeIncompleteSegments(storage: StorageManager) throws {
        let paths = try storage.listSegmentFiles()
        let fm = FileManager.default
        for path in paths {
            guard let attrs = try? fm.attributesOfItem(atPath: path),
                  let size = attrs[.size] as? Int64 else { continue }
            if size < 1024 {
                try? fm.removeItem(atPath: path)
            }
        }
    }
}
