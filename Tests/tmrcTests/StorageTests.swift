import Testing
import Foundation
@testable import tmrc

struct StorageTests {

    @Test("Storage root default from config")
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

    @Test("Directory layout after install")
    func directoryLayoutAfterInstall() throws {
        let tmp = FileManager.default.temporaryDirectory.path + "/tmrc-install-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: tmp) }
        let storageRoot = tmp
        let configPath = (storageRoot as NSString).appendingPathComponent("config.yaml")
        let installer = Installer(storageRoot: storageRoot, configPath: configPath)
        try installer.install()

        let fm = FileManager.default
        #expect(fm.fileExists(atPath: storageRoot))
        #expect(fm.fileExists(atPath: (storageRoot as NSString).appendingPathComponent("index")))
        #expect(fm.fileExists(atPath: (storageRoot as NSString).appendingPathComponent("segments")))
        #expect(fm.fileExists(atPath: configPath))
        let pidPath = (storageRoot as NSString).appendingPathComponent("tmrc.pid")
        #expect(!fm.fileExists(atPath: pidPath))
    }

    @Test("Index path per session")
    func indexPathPerSession() throws {
        let mgr = StorageManager(storageRoot: "/tmp/tmrc")
        #expect(mgr.indexPath(session: "default") == "/tmp/tmrc/index/default.sqlite")
    }

    @Test("Index path for named session")
    func indexPathNamedSession() throws {
        let mgr = StorageManager(storageRoot: "/tmp/tmrc")
        #expect(mgr.indexPath(session: "work") == "/tmp/tmrc/index/work.sqlite")
    }

    @Test("Retention max age evicts old segments")
    func retentionMaxAge() throws {
        let tmp = FileManager.default.temporaryDirectory.path + "/tmrc-retention-\(UUID().uuidString)"
        let segDir = (tmp as NSString).appendingPathComponent("segments")
        try FileManager.default.createDirectory(atPath: segDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tmp) }

        let oldDate = Calendar.current.date(byAdding: .day, value: -10, to: Date())!
        let path1 = (segDir as NSString).appendingPathComponent("old.mp4")
        FileManager.default.createFile(atPath: path1, contents: Data(repeating: 0, count: 100))
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: path1)
        let path2 = (segDir as NSString).appendingPathComponent("new.mp4")
        FileManager.default.createFile(atPath: path2, contents: Data(repeating: 0, count: 100))

        let retention = RetentionManager(maxAgeDays: 7, maxDiskBytes: 1_000_000)
        let deleted = try retention.evictIfNeeded(segmentsDirectory: segDir)
        #expect(deleted == 1)
        #expect(!FileManager.default.fileExists(atPath: path1))
        #expect(FileManager.default.fileExists(atPath: path2))
    }

    @Test("Retention under limits deletes nothing")
    func retentionUnderLimits() throws {
        let tmp = FileManager.default.temporaryDirectory.path + "/tmrc-retention-\(UUID().uuidString)"
        let segDir = (tmp as NSString).appendingPathComponent("segments")
        try FileManager.default.createDirectory(atPath: segDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tmp) }
        let path = (segDir as NSString).appendingPathComponent("a.mp4")
        FileManager.default.createFile(atPath: path, contents: Data(repeating: 0, count: 100))

        let retention = RetentionManager(maxAgeDays: 7, maxDiskBytes: 1_000_000)
        let deleted = try retention.evictIfNeeded(segmentsDirectory: segDir)
        #expect(deleted == 0)
        #expect(FileManager.default.fileExists(atPath: path))
    }

    @Test("Usage report - disk usage")
    func usageReport() throws {
        let tmp = FileManager.default.temporaryDirectory.path + "/tmrc-usage-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tmp) }
        let mgr = StorageManager(storageRoot: tmp)
        let usage = try mgr.diskUsage()
        #expect(usage >= 0)
    }
}
