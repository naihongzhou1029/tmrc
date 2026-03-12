import ArgumentParser
import Darwin
import Foundation

public struct RecordCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "record",
        abstract: "Start, stop, or check recording (daemon)."
    )

    @Flag(name: .long, help: "Start recording (spawn daemon if needed)")
    public var start = false

    @Flag(name: .long, help: "Stop recording (stop daemon, sync, exit)")
    public var stop = false

    @Flag(name: .long, help: "Show whether recording is in progress")
    public var status = false

    @Option(name: .long, help: "Session name (overrides config)")
    public var session: String?

    public init() {}

    public mutating func run() throws {
        if versionRequested { try printVersionAndExit() }
        if stop {
            try runStop()
            return
        }
        if status {
            try runStatus()
            return
        }
        try runStart()
    }

    private var versionRequested: Bool {
        (CommandLine.arguments.contains("--version"))
    }

    private func printVersionAndExit() throws -> Never {
        print(TMRCVersion.current)
        Darwin.exit(0)
    }

    private func runStart() throws {
        let configPath = ConfigLoader.resolveConfigPath(projectRoot: FileManager.default.currentDirectoryPath)
        let config: TMRCConfig
        if FileManager.default.fileExists(atPath: configPath) {
            config = try ConfigLoader.load(fromFile: configPath)
        } else {
            config = TMRCConfig.default()
        }
        let sessionName = session ?? config.session
        let storage = StorageManager(storageRoot: config.storageRoot)
        Logger.shared.configure(
            storage: storage,
            debugEnabled: CommandLine.arguments.contains("--debug")
        )
        let daemon = DaemonManager(storageManager: storage)
        do {
            try daemon.start(session: sessionName, configPath: configPath)
            print("Recording started (session: \(sessionName)).")
            Logger.shared.log("Recording start requested (session=\(sessionName))", level: .info, category: "cli")
        } catch DaemonError.alreadyRunning {
            print("Daemon is already recording (session: \(sessionName)).")
            Logger.shared.log("Recording start requested but daemon already running", level: .info, category: "cli")
        } catch {
            fputs("Failed to start recording: \(error.localizedDescription)\n", stderr)
            Logger.shared.log("Failed to start recording: \(error.localizedDescription)", level: .error, category: "cli")
            Darwin.exit(1)
        }
    }

    private func runStop() throws {
        let configPath = ConfigLoader.resolveConfigPath(projectRoot: FileManager.default.currentDirectoryPath)
        let storageRoot: String
        if FileManager.default.fileExists(atPath: configPath), let config = try? ConfigLoader.load(fromFile: configPath) {
            storageRoot = config.storageRoot
        } else {
            storageRoot = ("~/.tmrc/" as NSString).expandingTildeInPath
        }
        let daemon = DaemonManager(storageManager: StorageManager(storageRoot: storageRoot))
        if !daemon.isRunning() {
            print("No daemon is currently recording.")
            return
        }
        try daemon.stopIfRunning()
        print("Recording stopped.")
    }

    private func runStatus() throws {
        let configPath = ConfigLoader.resolveConfigPath(projectRoot: FileManager.default.currentDirectoryPath)
        let storageRoot: String
        if FileManager.default.fileExists(atPath: configPath), let config = try? ConfigLoader.load(fromFile: configPath) {
            storageRoot = config.storageRoot
        } else {
            storageRoot = ("~/.tmrc/" as NSString).expandingTildeInPath
        }
        let daemon = DaemonManager(storageManager: StorageManager(storageRoot: storageRoot))
        if daemon.isRunning(), let pid = daemon.readPID() {
            print("Recording: yes (PID \(pid))")
        } else {
            print("Recording: no")
        }
    }
}
