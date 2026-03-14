import AppKit
import Foundation

/// Manages an NSStatusItem (menu bar icon) that shows recording state and provides quick actions.
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let storage: StorageManager
    private let session: String
    private var statusMenuItem: NSMenuItem!
    private var segmentsMenuItem: NSMenuItem!
    private var diskMenuItem: NSMenuItem!
    private var updateTimer: Timer?

    init(storage: StorageManager, session: String) {
        self.storage = storage
        self.session = session
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        setupMenu()
        startPeriodicUpdate()
    }

    private func setupMenu() {
        guard let button = statusItem.button else { return }
        // Use SF Symbol for the recording indicator
        if let image = NSImage(systemSymbolName: "record.circle", accessibilityDescription: "tmrc recording") {
            image.isTemplate = true
            button.image = image
        } else {
            button.title = "⏺"
        }

        let menu = NSMenu()

        // Status header
        statusMenuItem = NSMenuItem(title: "Recording", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        menu.addItem(NSMenuItem.separator())

        // Info items
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

        // Actions
        let stopItem = NSMenuItem(title: "Stop Recording", action: #selector(stopRecording), keyEquivalent: "q")
        stopItem.target = self
        menu.addItem(stopItem)

        statusItem.menu = menu
        refreshStatus()
    }

    private func startPeriodicUpdate() {
        // Update status info every 30 seconds
        updateTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.refreshStatus()
        }
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
        updateTimer?.invalidate()
        updateTimer = nil
        NSStatusBar.system.removeStatusItem(statusItem)
    }
}
