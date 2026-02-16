import Foundation

/// Post macOS local notifications (toast). Uses osascript so no UserNotifications authorization is required.
public enum Notifier {
    /// Post a notification. Escapes title/body for AppleScript.
    public static func notify(title: String, body: String) {
        let t = title.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let b = body.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = "display notification \"\(b)\" with title \"\(t)\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
        process.waitUntilExit()
    }
}
