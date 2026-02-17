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
        let usageGB = Double(usage) / (1024 * 1024 * 1024)
        let retention = RetentionManager()
        let maxDiskGB = retention.maxDiskBytes / (1024 * 1024 * 1024)

        let session: String
        if FileManager.default.fileExists(atPath: configPath), let config = try? ConfigLoader.load(fromFile: configPath) {
            session = config.session
        } else {
            session = TMRCConfig.defaultSession
        }
        var indexManager = IndexManager(dbPath: storage.indexPath(session: session))
        let lastRecordingDuration: String? = (try? indexManager.totalRecordedDuration(session: session)).map { secs in
            let total = Int(secs.rounded())
            let days = total / 86400
            let hours = (total % 86400) / 3600
            let minutes = (total % 3600) / 60
            let seconds = total % 60
            return String(format: "%02d:%02d:%02d:%02d", days, hours, minutes, seconds)
        }

        print("Recording: \(recording ? "yes" : "no")")
        if let dur = lastRecordingDuration {
            print("Last recording: \(dur)")
        }
        print("Storage: \(storageRoot)")
        print("Disk usage: \(String(format: "%.1f", usageGB)) GB")
        print("Retention: max age \(retention.maxAgeDays) days, max disk \(maxDiskGB) GB")
        Logger.shared.log("Status queried (recording=\(recording), usageGB=\(String(format: "%.1f", usageGB)))", level: .info, category: "cli")
    }
}
