import ArgumentParser
import Darwin
import Foundation

public struct ExportCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "export",
        abstract: "Export a time range or query-matched segment to MP4 or GIF."
    )

    @Option(name: .long, help: "Start of range. Relative: \"now\", \"2h ago\", \"30m ago\", \"30min ago\", \"3d ago\", \"yesterday\". Absolute: \"YYYY-MM-DD HH:MM:SS\".")
    public var from: String?

    @Option(name: .long, help: "End of range. Same formats as --from.")
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
        let fromDate = from.flatMap { timeParser.parse($0) }
        let toDate = to.flatMap { timeParser.parse($0) }
        let outPath = outputPath ?? defaultExportPath(session: config.session, format: format)
        let engine = ExportEngine(storage: storage, indexManager: indexManager, session: config.session, quality: config.exportQuality)
        do {
            try engine.export(from: fromDate, to: toDate, query: query, outputPath: outPath, format: format)
            print("Exported to \(outPath)")
            Logger.shared.log("Export succeeded (session=\(config.session), format=\(format))", level: .info, category: "cli")
        } catch {
            fputs("\(error.localizedDescription)\n", stderr)
            Logger.shared.log("Export failed: \(error.localizedDescription)", level: .error, category: "cli")
            Darwin.exit(1)
        }
    }

    private func defaultExportPath(session: String, format: String) -> String {
        let cwd = FileManager.default.currentDirectoryPath
        let ext = format.lowercased() == "gif" ? "gif" : "mp4"
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let stamp = formatter.string(from: Date())
        return (cwd as NSString).appendingPathComponent("tmrc_export_\(session)_\(stamp).\(ext)")
    }
}
