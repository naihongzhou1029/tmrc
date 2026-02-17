import ArgumentParser
import Foundation

// Daemon is started with: tmrc --daemon <storage_root> <session> <config_path>
// Check before parsing so the daemon process doesn't need to parse subcommands.
@main
struct TmrcMain {
    static func main() {
        let args = CommandLine.arguments
        if args.count >= 5, args[1] == "--daemon" {
            let storageRoot = args[2]
            let session = args[3]
            let configPath = args[4]
            do {
                try DaemonEntry.runAsDaemon(storageRoot: storageRoot, session: session, configPath: configPath)
            } catch {
                fputs("Daemon failed: \(error.localizedDescription)\n", stderr)
                Darwin.exit(1)
            }
            return
        }
        do {
            var command = try Main.parseAsRoot()
            try command.run()
        } catch {
            if let exitError = error as? ExitCode {
                Darwin.exit(Int32(exitError.rawValue))
            }
            fputs("\(error)\n", stderr)
            Darwin.exit(1)
        }
    }
}

struct Main: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tmrc",
        abstract: "Time Machine Recall Commander — record, index, and recall your screen.",
        subcommands: [
            RecordCommand.self,
            AskCommand.self,
            ExportCommand.self,
            RebuildIndexCommand.self,
            InstallCommand.self,
            UninstallCommand.self,
            StatusCommand.self,
            WipeCommand.self,
        ]
    )

    @Flag(name: .shortAndLong, help: "Enable verbose / debug logging")
    var debug = false

    @Flag(name: .long, help: "Print version and exit")
    var version = false

    mutating func run() throws {
        if version {
            print(TMRCVersion.current)
            return
        }
        throw CleanExit.helpRequest(self)
    }
}
