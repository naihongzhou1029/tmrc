import AppKit
import Foundation

/// Manages an NSStatusItem (menu bar icon) that shows recording state and provides quick actions.
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let storage: StorageManager
    private let session: String
    private var recordingTimeMenuItem: NSMenuItem!
    private var segmentsMenuItem: NSMenuItem!
    private var diskMenuItem: NSMenuItem!
    private var clockTimer: Timer?
    private var statusTimer: Timer?
    private let recordingStartDate: Date

    init(storage: StorageManager, session: String) {
        self.storage = storage
        self.session = session
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // Use PID file modification date as recording start time; fall back to now.
        let pidAttrs = try? FileManager.default.attributesOfItem(atPath: storage.pidFilePath)
        self.recordingStartDate = (pidAttrs?[.modificationDate] as? Date) ?? Date()
        super.init()
        setupMenu()
        startTimers()
    }

    private func setupMenu() {
        guard let button = statusItem.button else { return }
        if let image = NSImage(systemSymbolName: "record.circle", accessibilityDescription: "tmrc recording") {
            image.isTemplate = true
            button.image = image
        } else {
            button.title = "⏺"
        }

        let menu = NSMenu()

        // Recording time (updated every second)
        recordingTimeMenuItem = NSMenuItem(title: "Recording: 00:00:00", action: nil, keyEquivalent: "")
        recordingTimeMenuItem.isEnabled = false
        menu.addItem(recordingTimeMenuItem)

        menu.addItem(NSMenuItem.separator())

        // Info items (updated every 30 seconds)
        segmentsMenuItem = NSMenuItem(title: "Segments: —", action: nil, keyEquivalent: "")
        segmentsMenuItem.isEnabled = false
        menu.addItem(segmentsMenuItem)

        diskMenuItem = NSMenuItem(title: "Disk: —", action: nil, keyEquivalent: "")
        diskMenuItem.isEnabled = false
        menu.addItem(diskMenuItem)

        let versionItem = NSMenuItem(title: "v\(TMRCVersion.current)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)

        menu.addItem(NSMenuItem.separator())

        let stopItem = NSMenuItem(title: "Stop Recording", action: #selector(stopRecording), keyEquivalent: "q")
        stopItem.target = self
        menu.addItem(stopItem)

        statusItem.menu = menu
        refreshRecordingTime()
        refreshStatus()
    }

    private func startTimers() {
        // Update elapsed recording time every second
        clockTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.refreshRecordingTime()
        }
        // Update segment count and disk usage every 30 seconds
        statusTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.refreshStatus()
        }
    }

    private func refreshRecordingTime() {
        let elapsed = Int(Date().timeIntervalSince(recordingStartDate))
        let h = elapsed / 3600
        let m = (elapsed % 3600) / 60
        let s = elapsed % 60
        recordingTimeMenuItem.title = String(format: "Recording: %02d:%02d:%02d", h, m, s)
    }

    private func refreshStatus() {
        let usage = (try? storage.diskUsage()) ?? 0
        let usageMB = Double(usage) / (1024 * 1024)
        let usageGB = usageMB / 1024

        var indexManager = IndexManager(dbPath: storage.indexPath(session: session))
        let count = (try? indexManager.countSegments(session: session)) ?? 0

        DispatchQueue.main.async { [weak self] in
            self?.segmentsMenuItem.title = "Segments: \(count)"
            if usageGB >= 1.0 {
                self?.diskMenuItem.title = String(format: "Disk: %.1f GB", usageGB)
            } else {
                self?.diskMenuItem.title = String(format: "Disk: %.0f MB", usageMB)
            }
        }
    }

    @objc private func stopRecording() {
        Logger.shared.log("Stop requested from menu bar", level: .info, category: "daemon")
        DaemonEntry.signalReceived = true
    }

    func invalidate() {
        clockTimer?.invalidate()
        statusTimer?.invalidate()
        clockTimer = nil
        statusTimer = nil
        NSStatusBar.system.removeStatusItem(statusItem)
    }
}
