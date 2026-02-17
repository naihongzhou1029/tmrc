import ArgumentParser
import Darwin
import Foundation

public struct WipeCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "wipe",
        abstract: "Remove all recorded segments and index entries. Daemon (if running) keeps running."
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

        let fm = FileManager.default
        var segmentsDeleted = 0
        for path in try storage.listSegmentFiles() {
            try? fm.removeItem(atPath: path)
            segmentsDeleted += 1
        }

        let indexDir = storage.indexDirectory
        if fm.fileExists(atPath: indexDir) {
            let contents = (try? fm.contentsOfDirectory(atPath: indexDir)) ?? []
            for name in contents where name.hasSuffix(".sqlite") {
                var indexManager = IndexManager(dbPath: (indexDir as NSString).appendingPathComponent(name))
                try indexManager.deleteAllSegments()
            }
        }

        print("Wiped \(segmentsDeleted) segment(s) and cleared index. Daemon (if running) continues recording.")
        Logger.shared.log("Wipe completed (segmentsDeleted=\(segmentsDeleted))", level: .info, category: "cli")
    }
}
