import Testing
import Foundation
@testable import tmrc

struct ConfigTests {

    @Test("Sample rate default when key missing")
    func sampleRateDefault() throws {
        let yaml = ""
        let config = try ConfigLoader.loadFromYAML(yaml)
        #expect(config.sampleRateMs == 100)
    }

    @Test("Sample rate override")
    func sampleRateOverride() throws {
        let yaml = "sample_rate_ms: 16.1"
        let config = try ConfigLoader.loadFromYAML(yaml)
        #expect(config.sampleRateMs == 16.1)
    }

    @Test("Sample rate invalid (zero) fails or uses default")
    func sampleRateInvalid() throws {
        let yaml = "sample_rate_ms: 0"
        do {
            let config = try ConfigLoader.loadFromYAML(yaml)
            #expect(config.sampleRateMs == 100)
        } catch ConfigError.invalidSampleRate {
            // acceptable: validation error
        } catch {
            throw error
        }
    }

    @Test("Session name default")
    func sessionDefault() throws {
        let yaml = ""
        let config = try ConfigLoader.loadFromYAML(yaml)
        #expect(config.session == "default")
    }

    @Test("Session name from config")
    func sessionFromConfig() throws {
        let yaml = "session: work"
        let config = try ConfigLoader.loadFromYAML(yaml)
        #expect(config.session == "work")
    }

    @Test("Capture mode default")
    func captureModeDefault() throws {
        let yaml = ""
        let config = try ConfigLoader.loadFromYAML(yaml)
        #expect(config.captureMode == .full_screen)
    }

    @Test("Display default")
    func displayDefault() throws {
        let yaml = ""
        let config = try ConfigLoader.loadFromYAML(yaml)
        #expect(config.display == .main)
    }

    @Test("Audio default")
    func audioDefault() throws {
        let yaml = ""
        let config = try ConfigLoader.loadFromYAML(yaml)
        #expect(config.audioEnabled == false)
    }

    @Test("Audio enabled")
    func audioEnabled() throws {
        let yaml = "audio_enabled: true"
        let config = try ConfigLoader.loadFromYAML(yaml)
        #expect(config.audioEnabled == true)
    }

    @Test("Lock/sleep default")
    func lockSleepDefault() throws {
        let yaml = ""
        let config = try ConfigLoader.loadFromYAML(yaml)
        #expect(config.recordWhenLockedOrSleeping == false)
    }

    @Test("Storage root default")
    func storageRootDefault() throws {
        let yaml = ""
        let config = try ConfigLoader.loadFromYAML(yaml)
        let expected = ("~/.tmrc/" as NSString).expandingTildeInPath
        #expect(config.storageRoot == expected)
    }

    @Test("Storage root override")
    func storageRootOverride() throws {
        let yaml = "storage_root: /tmp/tmrc-test"
        let config = try ConfigLoader.loadFromYAML(yaml)
        #expect(config.storageRoot == "/tmp/tmrc-test")
    }

    @Test("Index mode default")
    func indexModeDefault() throws {
        let yaml = ""
        let config = try ConfigLoader.loadFromYAML(yaml)
        #expect(config.indexMode == .normal)
    }

    @Test("Index mode advanced and normal")
    func indexModeValues() throws {
        let configA = try ConfigLoader.loadFromYAML("index_mode: advanced")
        #expect(configA.indexMode == .advanced)
        let configN = try ConfigLoader.loadFromYAML("index_mode: normal")
        #expect(configN.indexMode == .normal)
    }

    @Test("Index mode invalid fails")
    func indexModeInvalid() throws {
        #expect(throws: ConfigError.self) {
            _ = try ConfigLoader.loadFromYAML("index_mode: foo")
        }
    }

    @Test("OCR languages default")
    func ocrLanguagesDefault() throws {
        let yaml = ""
        let config = try ConfigLoader.loadFromYAML(yaml)
        #expect(config.ocrRecognitionLanguages == ["en-US", "zh-Hant", "zh-Hans"])
    }

    @Test("OCR languages override")
    func ocrLanguagesOverride() throws {
        let yaml = """
        ocr_recognition_languages:
          - ja-JP
          - ko-KR
        """
        let config = try ConfigLoader.loadFromYAML(yaml)
        #expect(config.ocrRecognitionLanguages == ["ja-JP", "ko-KR"])
    }
}
