import Foundation
import Yams

/// Partial config for decoding YAML where missing keys are optional.
private struct TMRCConfigPartial: Codable {
    var sample_rate_ms: Double?
    var display: String?
    var capture_mode: String?
    var audio_enabled: Bool?
    var record_when_locked_or_sleeping: Bool?
    var session: String?
    var storage_root: String?
    var index_mode: String?
    var ocr_recognition_languages: [String]?
    var ocr_granularity: String?
    var ask_default_range: String?
    var export_quality: String?
}

public struct ConfigLoader {
    /// Resolve config file path: TMRC_CONFIG_PATH env, then project root config.yaml (dev), else ~/.config/tmrc/config.yaml.
    public static func resolveConfigPath(projectRoot: String? = nil) -> String {
        if let env = ProcessInfo.processInfo.environment["TMRC_CONFIG_PATH"], !env.isEmpty {
            return (env as NSString).expandingTildeInPath
        }
        if let root = projectRoot, !root.isEmpty {
            let projectConfig = (root as NSString).appendingPathComponent("config.yaml")
            if FileManager.default.fileExists(atPath: projectConfig) {
                return projectConfig
            }
        }
        let cwd = FileManager.default.currentDirectoryPath
        let cwdConfig = (cwd as NSString).appendingPathComponent("config.yaml")
        if FileManager.default.fileExists(atPath: cwdConfig) {
            return cwdConfig
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return (home as NSString).appendingPathComponent(".config/tmrc/config.yaml")
    }

    /// Load config from file path, merging with defaults.
    public static func load(fromFile path: String) throws -> TMRCConfig {
        guard FileManager.default.fileExists(atPath: path) else {
            throw ConfigError.fileNotFound(path)
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try load(from: data)
    }

    /// Load config from YAML data (e.g. for tests). Empty or whitespace-only data returns default config.
    public static func load(from data: Data) throws -> TMRCConfig {
        if data.isEmpty || data.allSatisfy({ $0 == 0x20 || $0 == 0x0a || $0 == 0x0d || $0 == 0x09 }) {
            var config = TMRCConfig.default()
            try config.resolveAndValidate()
            return config
        }
        let decoder = YAMLDecoder()
        let partial: TMRCConfigPartial
        do {
            partial = try decoder.decode(TMRCConfigPartial.self, from: data)
        } catch {
            throw ConfigError.invalidYAML(error.localizedDescription)
        }
        var config = try mergePartial(partial)
        try config.resolveAndValidate()
        return config
    }

    /// Load config from YAML string (for tests). Empty string returns default config.
    public static func loadFromYAML(_ yaml: String) throws -> TMRCConfig {
        guard let data = yaml.data(using: .utf8) else {
            throw ConfigError.invalidYAML("Invalid UTF-8")
        }
        return try load(from: data)
    }

    private static func mergePartial(_ p: TMRCConfigPartial) throws -> TMRCConfig {
        var out = TMRCConfig.default()
        if let v = p.sample_rate_ms { out.sampleRateMs = v }
        if let s = p.display, let v = DisplayOption(rawValue: s) { out.display = v }
        if let s = p.capture_mode, let v = CaptureMode(rawValue: s) { out.captureMode = v }
        if let v = p.audio_enabled { out.audioEnabled = v }
        if let v = p.record_when_locked_or_sleeping { out.recordWhenLockedOrSleeping = v }
        if let v = p.session, !v.isEmpty { out.session = v }
        if let v = p.storage_root, !v.isEmpty { out.storageRoot = v }
        if let s = p.index_mode {
            guard let v = IndexMode(rawValue: s) else {
                throw ConfigError.invalidIndexMode(s)
            }
            out.indexMode = v
        }
        if let v = p.ocr_recognition_languages, !v.isEmpty { out.ocrRecognitionLanguages = v }
        if let s = p.ocr_granularity, let v = OCRGranularity(rawValue: s) { out.ocrGranularity = v }
        if let v = p.ask_default_range, !v.isEmpty { out.askDefaultRange = v }
        if let s = p.export_quality, let v = ExportQuality(rawValue: s) { out.exportQuality = v }
        return out
    }
}
