import ArgumentParser
import Darwin
import Foundation

public struct UninstallCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "uninstall",
        abstract: "Stop daemon and optionally remove data."
    )

    @Flag(name: .long, help: "Remove storage and config data")
    public var removeData = false

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
        let installer = Installer(storageRoot: storageRoot, configPath: configPath)
        Logger.shared.configure(
            storage: installer.storageManager,
            debugEnabled: CommandLine.arguments.contains("--debug")
        )
        try DaemonManager(storageManager: StorageManager(storageRoot: storageRoot)).stopIfRunning()
        try installer.uninstall(removeData: removeData)
        print(removeData ? "Uninstalled (data removed)." : "Daemon stopped. Data kept at \(storageRoot).")
        Logger.shared.log("Uninstall completed (storageRoot=\(storageRoot), removeData=\(removeData))", level: .info, category: "cli")
    }
}
