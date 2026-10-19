import AppKit
import ApplicationServices

enum Permissions {

    /// Accessibility (TCC) — required to create an event tap that can swallow events.
    static var accessibility: Bool {
        AXIsProcessTrusted()
    }

    /// Input Monitoring (TCC) — required to receive keyboard events at all on 10.15+.
    static var inputMonitoring: Bool {
        CGPreflightListenEventAccess()
    }

    static var allGranted: Bool {
        accessibility && inputMonitoring
    }

    /// Shows the system prompts. Each prompt is only shown once per app identity,
    /// so always pair this with a button that opens System Settings.
    static func requestAll() {
        if !accessibility {
            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        }
        if !inputMonitoring {
            _ = CGRequestListenEventAccess()
        }
    }

    static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    static func openInputMonitoringSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    private static func open(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }
}
