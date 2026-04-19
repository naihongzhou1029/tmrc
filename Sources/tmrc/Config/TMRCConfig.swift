import Foundation

/// Indexing/recall mode: normal (lighter) or advanced (full OCR, semantic, LLM).
public enum IndexMode: String, Codable, CaseIterable {
    case normal
    case advanced
}

/// Capture mode for screen recording.
public enum CaptureMode: String, Codable, CaseIterable {
    case full_screen
    case window
    case app
}

/// Display capture option.
public enum DisplayOption: String, Codable, CaseIterable {
    case main
    case combined
}

/// Export quality level.
public enum ExportQuality: String, Codable, CaseIterable {
    case low
    case medium
    case high
}

/// OCR granularity (Advanced mode can configure; Normal always per_segment_summary).
public enum OCRGranularity: String, Codable, CaseIterable {
    case per_segment_summary
    case per_frame
    case keyframes
}

public struct TMRCConfig: Codable {
    /// Sample rate for event parsing (ms). Default 100 = 10 FPS.
    public var sampleRateMs: Double
    /// Which display(s) to capture.
    public var display: DisplayOption
    /// Capture mode: full_screen, window, or app.
    public var captureMode: CaptureMode
    /// Whether to record audio.
    public var audioEnabled: Bool
    /// Record when display is locked or machine is sleeping.
    public var recordWhenLockedOrSleeping: Bool
    /// Default session name.
    public var session: String
    /// Storage root path (tilde-expanded).
    public var storageRoot: String
    /// Index mode: normal or advanced.
    public var indexMode: IndexMode
    /// OCR recognition languages (BCP 47).
    public var ocrRecognitionLanguages: [String]
    /// OCR granularity (Advanced only; Normal ignores).
    public var ocrGranularity: OCRGranularity
    /// Default time range for "search" (e.g. "24h").
    public var searchDefaultRange: String
    /// Export quality: low, medium, high.
    public var exportQuality: ExportQuality
    /// When true, clear tmrc.log when starting recording from CLI (daemon start). Does not clear on in-process restarts. Default true.
    public var clearLogOnStart: Bool
    /// When true, show a menu bar icon while the daemon is recording. Default true.
    public var menuBarIcon: Bool

    enum CodingKeys: String, CodingKey {
        case sampleRateMs = "sample_rate_ms"
        case display
        case captureMode = "capture_mode"
        case audioEnabled = "audio_enabled"
        case recordWhenLockedOrSleeping = "record_when_locked_or_sleeping"
        case session
        case storageRoot = "storage_root"
        case indexMode = "index_mode"
        case ocrRecognitionLanguages = "ocr_recognition_languages"
        case ocrGranularity = "ocr_granularity"
        case searchDefaultRange = "search_default_range"
        case exportQuality = "export_quality"
        case clearLogOnStart = "clear_log_on_start"
        case menuBarIcon = "menu_bar_icon"
    }

    public static let defaultSampleRateMs = 100.0
    public static let defaultSession = "default"
    public static let defaultStorageRoot = "~/.tmrc/"
    public static let defaultOcrLanguages = ["en-US", "zh-Hant", "zh-Hans"]
    public static let defaultSearchDefaultRange = "24h"
    public static let minSampleRateMs = 1.0
    public static let maxSampleRateMs = 1000.0

    public static func `default`() -> TMRCConfig {
        TMRCConfig(
            sampleRateMs: defaultSampleRateMs,
            display: .main,
            captureMode: .full_screen,
            audioEnabled: false,
            recordWhenLockedOrSleeping: false,
            session: defaultSession,
            storageRoot: defaultStorageRoot,
            indexMode: .normal,
            ocrRecognitionLanguages: defaultOcrLanguages,
            ocrGranularity: .per_segment_summary,
            searchDefaultRange: defaultSearchDefaultRange,
            exportQuality: .high,
            clearLogOnStart: true,
            menuBarIcon: true
        )
    }

    /// Expand storage_root tilde and validate numeric/enum fields.
    public mutating func resolveAndValidate() throws {
        storageRoot = (storageRoot as NSString).expandingTildeInPath
        if sampleRateMs < Self.minSampleRateMs || sampleRateMs > Self.maxSampleRateMs {
            throw ConfigError.invalidSampleRate(sampleRateMs)
        }
        if session.isEmpty {
            session = Self.defaultSession
        }
        if ocrRecognitionLanguages.isEmpty {
            ocrRecognitionLanguages = Self.defaultOcrLanguages
        }
    }
}

public enum ConfigError: LocalizedError {
    case fileNotFound(String)
    case invalidYAML(String)
    case invalidSampleRate(Double)
    case invalidIndexMode(String)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let path): return "Config file not found: \(path)"
        case .invalidYAML(let msg): return "Invalid config YAML: \(msg)"
        case .invalidSampleRate(let v): return "sample_rate_ms must be between \(TMRCConfig.minSampleRateMs) and \(TMRCConfig.maxSampleRateMs), got \(v)"
        case .invalidIndexMode(let v): return "index_mode must be 'normal' or 'advanced', got '\(v)'"
        }
    }
}
