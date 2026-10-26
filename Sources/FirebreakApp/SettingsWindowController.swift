import SwiftUI
import AppKit
import FirebreakCore

/// Hosts SettingsView in a plain NSWindow. The SwiftUI `Settings` scene can't be opened
/// reliably from an accessory (no Dock icon) app on macOS 14+, so the window is owned here.
@MainActor
final class SettingsWindowController {
    private let watchdog: WatchdogService
    private let preferences: AppPreferences
    private var window: NSWindow?

    init(watchdog: WatchdogService, preferences: AppPreferences) {
        self.watchdog = watchdog
        self.preferences = preferences
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let hosting = NSHostingController(rootView: SettingsView(watchdog: watchdog, preferences: preferences))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Firebreak Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}
