import ArgumentParser
import Darwin
import Foundation

public struct AskCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "ask",
        abstract: "Ask a natural-language question; get text answer with time references."
    )

    @Argument(help: "Natural-language question")
    public var query: String

    @Option(name: .long, help: "Search from (e.g. \"2h ago\", \"2025-02-15 14:00:00\")")
    public var since: String?

    @Option(name: .long, help: "Search until (e.g. \"1h ago\", \"now\")")
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
        let engine = AskEngine(indexManager: indexManager, session: config.session, defaultRange: config.askDefaultRange)
        let (answer, _) = try engine.ask(query: query, since: since, until: until)
        print(answer)
        Logger.shared.log("Ask executed (session=\(config.session))", level: .info, category: "cli")
    }
}
