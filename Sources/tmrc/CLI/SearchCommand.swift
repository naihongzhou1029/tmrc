import ArgumentParser
import Darwin
import Foundation

public struct SearchCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "search",
        abstract: "Keyword search in recordings; get text answer with time references.",
        discussion: """
        Examples:
          tmrc search "Xcode"                                    # Search without time range (uses default 24h)
          tmrc search "terminal" --since "2h ago" --until "now" # Search with time range
          tmrc search "error" --since "yesterday"                # Search since yesterday
        """
    )

    @Argument(help: "Natural-language question")
    public var query: String

    @Option(name: .long, help: "Search from. Relative: \"now\", \"2h ago\", \"30m ago\", \"30min ago\", \"3d ago\", \"yesterday\". Absolute: \"YYYY-MM-DD HH:MM:SS\".")
    public var since: String?

    @Option(name: .long, help: "Search until. Same formats as --since.")
    public var until: String?

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
        let engine = SearchEngine(indexManager: indexManager, session: config.session, defaultRange: config.searchDefaultRange)
        let (answer, _) = try engine.search(query: query, since: since, until: until)
        print(answer)
        Logger.shared.log("Search executed (session=\(config.session))", level: .info, category: "cli")
    }
}
