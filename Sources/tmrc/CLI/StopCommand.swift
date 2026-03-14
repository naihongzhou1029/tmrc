import ArgumentParser
import Darwin
import Foundation

public struct StopCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "stop",
        abstract: "Stop recording (stop daemon, sync, exit)."
    )

    public init() {}

    public mutating func run() throws {
        if CommandLine.arguments.contains("--version") {
            print(TMRCVersion.current)
            Darwin.exit(0)
        }
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
}
