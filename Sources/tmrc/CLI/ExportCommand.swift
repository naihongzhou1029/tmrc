import ArgumentParser
import Darwin
import Foundation

public struct ExportCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "export",
        abstract: "Export a time range or query-matched segment to MP4 or GIF."
    )

    @Option(name: .long, help: "Start of range (absolute or relative, e.g. \"1h ago\")")
    public var from: String?

    @Option(name: .long, help: "End of range (absolute or relative)")
    public var to: String?

    @Option(name: .long, help: "Export range matching this query (merged)")
    public var query: String?

    @Option(name: .shortAndLong, help: "Output file path")
    public var outputPath: String?

    @Option(name: .long, help: "Output format: mp4 or gif")
    public var format: String = "mp4"

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
        let storage = StorageManager(storageRoot: config.storageRoot)
        Logger.shared.configure(
            storage: storage,
            debugEnabled: CommandLine.arguments.contains("--debug")
        )
        let indexManager = IndexManager(dbPath: storage.indexPath(session: config.session))
        let timeParser = TimeRangeParser()
        let fromDate = from.flatMap { try? timeParser.parse($0) } ?? nil
        let toDate = to.flatMap { try? timeParser.parse($0) } ?? nil
        let engine = ExportEngine(storage: storage, indexManager: indexManager, session: config.session)
        do {
            try engine.export(from: fromDate, to: toDate, query: query, outputPath: outputPath ?? "", format: format)
            print("Exported to \(outputPath ?? "")")
            Logger.shared.log("Export succeeded (session=\(config.session), format=\(format))", level: .info, category: "cli")
        } catch {
            fputs("\(error.localizedDescription)\n", stderr)
            Logger.shared.log("Export failed: \(error.localizedDescription)", level: .error, category: "cli")
            Darwin.exit(1)
        }
    }
}
