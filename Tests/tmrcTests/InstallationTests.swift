import Testing
import Foundation
@testable import tmrc

struct InstallationTests {

    @Test("Installer.install creates storage and config")
    func installerInstall() throws {
        let tmp = FileManager.default.temporaryDirectory.path + "/tmrc-test-install-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: tmp) }
        
        let storageRoot = (tmp as NSString).appendingPathComponent("storage")
        let configPath = (tmp as NSString).appendingPathComponent("config.yaml")
        let installer = Installer(storageRoot: storageRoot, configPath: configPath)
        
        try installer.install()
        
        let fm = FileManager.default
        #expect(fm.fileExists(atPath: storageRoot))
        #expect(fm.fileExists(atPath: (storageRoot as NSString).appendingPathComponent("index")))
        #expect(fm.fileExists(atPath: (storageRoot as NSString).appendingPathComponent("segments")))
        #expect(fm.fileExists(atPath: configPath))
        
        // Verify default config contains expected keys
        let configContent = try String(contentsOfFile: configPath)
        #expect(configContent.contains("storage_root: ~/.tmrc/"))
        #expect(configContent.contains("sample_rate_ms: 100"))
    }

    @Test("Installer.uninstall removes storage if requested")
    func installerUninstall() throws {
        let tmp = FileManager.default.temporaryDirectory.path + "/tmrc-test-uninstall-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: tmp) }
        
        let storageRoot = (tmp as NSString).appendingPathComponent("storage")
        let configPath = (tmp as NSString).appendingPathComponent("config.yaml")
        let installer = Installer(storageRoot: storageRoot, configPath: configPath)
        
        try installer.install()
        #expect(FileManager.default.fileExists(atPath: storageRoot))
        
        // Uninstall with removeData = false
        try installer.uninstall(removeData: false)
        #expect(FileManager.default.fileExists(atPath: storageRoot))
        
        // Uninstall with removeData = true
        try installer.uninstall(removeData: true)
        #expect(!FileManager.default.fileExists(atPath: storageRoot))
    }
}
