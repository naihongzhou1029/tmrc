import AppKit
import Foundation
import Darwin

/// When running as daemon (tmrc --daemon), this runs the capture loop. Called from main after parsing.
public struct DaemonEntry {
    public static func runAsDaemon(storageRoot: String, session: String, configPath: String) throws {
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

        let config: TMRCConfig
        if FileManager.default.fileExists(atPath: configPath) {
            config = try ConfigLoader.load(fromFile: configPath)
        } else {
            config = TMRCConfig.default()
        }

        if config.clearLogOnStart {
            let logURL = URL(fileURLWithPath: storage.logFilePath)
            if FileManager.default.fileExists(atPath: logURL.path),
               let handle = try? FileHandle(forWritingTo: logURL) {
                try? handle.truncate(atOffset: 0)
                try? handle.close()
            }
        }

        // Crash recovery: remove incomplete segment files (0 or very small) from previous run.
        try removeIncompleteSegments(storage: storage)

        let runner = DaemonRunner(storage: storage, session: session, config: config)
        Logger.shared.log("Daemon entering main loop (sampleInterval=\(config.sampleRateMs)ms, menuBarIcon=\(config.menuBarIcon))", level: .info, category: "daemon")

        if config.menuBarIcon {
            // Run with NSApplication event loop for menu bar icon.
            // The capture loop runs on a background thread; NSApp.run() owns the main thread.
            let appDelegate = DaemonAppDelegate(storage: storage, session: session)
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
            app.delegate = appDelegate

            DispatchQueue.global(qos: .userInitiated).async {
                runner.runUntilSignalled()
                // Capture loop exited (signal or error) — tear down
                cleanup(storage: storage)
                DispatchQueue.main.async {
                    app.terminate(nil)
                }
            }

            app.run()
            // NSApp.run() returns after terminate
            Darwin.exit(0)
        } else {
            // Headless mode: original behavior
            defer {
                cleanup(storage: storage)
                Darwin.exit(0)
            }
            runner.runUntilSignalled()
            Darwin.exit(0)
        }
    }

    static var signalReceived = false

    private static func cleanup(storage: StorageManager) {
        Logger.shared.log("Daemon shutting down (signalReceived=\(DaemonEntry.signalReceived))", level: .info, category: "daemon")
        try? FileManager.default.removeItem(atPath: storage.pidFilePath)
        try? FileManager.default.removeItem(atPath: storage.socketPath)
    }

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
