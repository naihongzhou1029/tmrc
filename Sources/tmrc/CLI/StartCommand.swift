import ArgumentParser
import Darwin
import Foundation

public struct StartCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "start",
        abstract: "Start recording (spawn daemon if needed)."
    )

    @Option(name: .long, help: "Session name (overrides config)")
    public var session: String?

    public init() {}

    public mutating func run() throws {
        if CommandLine.arguments.contains("--version") {
            print(TMRCVersion.current)
            Darwin.exit(0)
        }
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
}
