import ArgumentParser
import Darwin
import Foundation

public struct StatusCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show daemon status, last segment, disk usage."
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
        let storage = StorageManager(storageRoot: storageRoot)
        Logger.shared.configure(
            storage: storage,
            debugEnabled: CommandLine.arguments.contains("--debug")
        )
        let daemon = DaemonManager(storageManager: storage)
        let recording = daemon.isRunning()
        let usage = (try? storage.diskUsage()) ?? 0
        let usageMB = usage / (1024 * 1024)
        let retention = RetentionManager()
        let maxDiskGB = retention.maxDiskBytes / (1024 * 1024 * 1024)

        print("Recording: \(recording ? "yes" : "no")")
        print("Storage: \(storageRoot)")
        print("Disk usage: \(usageMB) MB")
        print("Retention: max age \(retention.maxAgeDays) days, max disk \(maxDiskGB) GB")
        Logger.shared.log("Status queried (recording=\(recording), usageMB=\(usageMB))", level: .info, category: "cli")
    }
}
