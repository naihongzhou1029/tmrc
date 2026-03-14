import AppKit
import Foundation

/// NSApplicationDelegate for daemon mode. Sets the app as accessory (no Dock icon, no app menu)
/// and hosts the StatusBarController.
final class DaemonAppDelegate: NSObject, NSApplicationDelegate {
    private var statusBar: StatusBarController?
    private let storage: StorageManager
    private let session: String

    init(storage: StorageManager, session: String) {
        self.storage = storage
        self.session = session
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBar = StatusBarController(storage: storage, session: session)
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusBar?.invalidate()
    }
}
