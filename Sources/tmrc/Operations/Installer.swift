import Foundation

/// Install: create storage dirs and optionally default config. Uninstall: stop daemon and optionally remove data.
public struct Installer {
    public let storageManager: StorageManager
    public let configPath: String

    public init(storageRoot: String, configPath: String) {
        self.storageManager = StorageManager(storageRoot: storageRoot)
        self.configPath = configPath
    }

    /// Create storage_root, index/, segments/. Does not create tmrc.pid (created when daemon starts).
    /// If config at configPath does not exist, write a default config there (for installed CLI: ~/.config/tmrc/config.yaml).
    public func install() throws {
        try storageManager.createLayoutIfNeeded()
        Logger.shared.configure(
            storage: storageManager,
            debugEnabled: CommandLine.arguments.contains("--debug")
        )
        Logger.shared.log("Install invoked (storageRoot=\(storageManager.storageRoot), configPath=\(configPath))", level: .info, category: "cli")
        let fm = FileManager.default
        let configDir = (configPath as NSString).deletingLastPathComponent
        if !fm.fileExists(atPath: configDir) {
            try fm.createDirectory(atPath: configDir, withIntermediateDirectories: true, attributes: nil)
        }
        if !fm.fileExists(atPath: configPath) {
            try writeDefaultConfig(to: configPath)
        }
    }

    /// Stop daemon (if running), then optionally remove storage_root and config.
    public func uninstall(removeData: Bool) throws {
        // Daemon stop is done by CLI (Phase 3); here we only remove dirs if requested.
        if removeData {
            let root = storageManager.storageRoot
            if FileManager.default.fileExists(atPath: root) {
                try FileManager.default.removeItem(atPath: root)
            }
        }
    }

    private func writeDefaultConfig(to path: String) throws {
        let content = """
        # tmrc configuration (default)
        sample_rate_ms: 32.2
        display: main
        capture_mode: full_screen
        audio_enabled: false
        record_when_locked_or_sleeping: false
        session: default
        storage_root: ~/.tmrc/
        index_mode: normal
        ocr_recognition_languages:
          - en-US
          - zh-Hant
          - zh-Hans
        ocr_granularity: per_segment_summary
        ask_default_range: 24h
        export_quality: high

        """
        try content.write(toFile: path, atomically: true, encoding: .utf8)
    }
}
