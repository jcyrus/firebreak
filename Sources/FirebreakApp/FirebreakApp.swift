import SwiftUI
import AppKit
import FirebreakCore

@main
struct FirebreakApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The menu bar UI is an AppKit NSStatusItem owned by AppDelegate. SwiftUI's MenuBarExtra
        // rebuilds its label on every observed change, which drops clicks and dismisses the panel
        // while the alert cadence is updating the CPU% every 1.5s.
        //
        // SwiftUI still needs one scene. A never-inserted MenuBarExtra owns no window, unlike
        // `Settings { EmptyView() }`, which macOS restored on relaunch as a blank "Firebreak Settings" window.
        MenuBarExtra("Firebreak", systemImage: "flame", isInserted: .constant(false)) {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let watchdog = WatchdogService()
    private let preferences = AppPreferences()
    private var statusItemController: StatusItemController?
    private var settingsWindowController: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let settings = SettingsWindowController(watchdog: watchdog, preferences: preferences)
        settingsWindowController = settings
        statusItemController = StatusItemController(
            watchdog: watchdog,
            preferences: preferences,
            openSettings: { settings.show() }
        )
        // Monitor from launch so the menu bar badge is live before the popover is ever opened.
        watchdog.startMonitoring()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        watchdog.resumeFrozenOnQuit()
    }
}
