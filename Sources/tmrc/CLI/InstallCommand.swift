import ArgumentParser
import Darwin
import Foundation

public struct InstallCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "install",
        abstract: "Create storage dirs and default config if missing."
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
        let installer = Installer(storageRoot: storageRoot, configPath: configPath)
        try installer.install()
        print("Installed: storage at \(storageRoot), config at \(configPath)")
        Logger.shared.log("Install CLI completed (storageRoot=\(storageRoot), configPath=\(configPath))", level: .info, category: "cli")
    }
}
