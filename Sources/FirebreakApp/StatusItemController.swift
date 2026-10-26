import SwiftUI
import AppKit
import Observation
import FirebreakCore

/// Owns the menu bar status item and its popover.
///
/// The button is updated in place, and only when the rendered icon or text actually changes,
/// so it stays clickable while the watchdog is publishing updates every 1.5s in alert cadence.
@MainActor
final class StatusItemController: NSObject {
    private let watchdog: WatchdogService
    private let preferences: AppPreferences
    private let openSettings: () -> Void
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var renderedSymbol: String?
    private var renderedTitle: String?
    private var renderedTint: NSColor?
    private static let autosaveName = "firebreak_status"

    init(watchdog: WatchdogService, preferences: AppPreferences, openSettings: @escaping () -> Void) {
        self.watchdog = watchdog
        self.preferences = preferences
        self.openSettings = openSettings
        // Name the item in the same step it is created, before anything else touches it. macOS keys the
        // saved ⌘-drag position ("NSStatusItem Preferred Position firebreak_status") by this name; renaming
        // later left the item registered as "Item-0", so a pin right of Hidden Bar's separator was never
        // saved and the item fell back into the hidden section on every relayout.
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = Self.autosaveName
        self.statusItem = item
        super.init()

        let hosting = NSHostingController(rootView: MenuBarView(watchdog: watchdog) { [weak self] in
            self?.showSettings()
        })
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.animates = false

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(handleClick(_:))
            // Fire on mouse-down: a click is never lost to a redraw between down and up.
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
            button.imagePosition = .imageLeading
        }

        render()
        observeReport()
    }

    // MARK: - Rendering

    private func observeReport() {
        withObservationTracking {
            _ = watchdog.latestReport
            _ = watchdog.activeSwarms
            _ = watchdog.displayTemperatureCelsius
            _ = watchdog.temperatureThresholdCelsius
            _ = preferences.showCPUInMenuBar
            _ = preferences.showTemperatureInMenuBar
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.render()
                self?.observeReport()
            }
        }
    }

    private func render() {
        guard let button = statusItem.button else { return }
        let report = watchdog.latestReport

        let symbol: String
        switch report.severity {
        case .critical: symbol = "exclamationmark.triangle.fill"
        case .warning: symbol = "flame.fill"
        case .normal: symbol = watchdog.frozenSwarms.isEmpty ? "flame" : "snowflake"
        }

        // Keep the 2s sensor loop running only while the temperature is actually displayed.
        if watchdog.wantsLiveTemperature != preferences.showTemperatureInMenuBar {
            watchdog.wantsLiveTemperature = preferences.showTemperatureInMenuBar
        }

        let temperature = watchdog.displayTemperatureCelsius
        let title = MenuBarTitle.make(
            temperatureCelsius: temperature,
            showTemperature: preferences.showTemperatureInMenuBar,
            report: report,
            showCPU: preferences.showCPUInMenuBar
        )

        // Plain menu bar colour normally; orange within 10°C of the trip threshold, red at it.
        var tint: NSColor?
        if preferences.showTemperatureInMenuBar, let temperature {
            let threshold = watchdog.temperatureThresholdCelsius
            if temperature >= threshold {
                tint = .systemRed
            } else if temperature >= threshold - 10.0 {
                tint = .systemOrange
            }
        }

        if symbol != renderedSymbol {
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Firebreak")
            image?.isTemplate = true
            button.image = image
            renderedSymbol = symbol
        }
        // Only touch the button when the whole-degree text or tint changes, so most 2s sensor
        // reads cause no redraw and clicks are never dropped mid-update.
        if title != renderedTitle || tint != renderedTint {
            let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
            var attributes: [NSAttributedString.Key: Any] = [.font: font]
            if let tint { attributes[.foregroundColor] = tint }
            button.attributedTitle = NSAttributedString(string: title, attributes: attributes)
            renderedTitle = title
            renderedTint = tint
        }
        button.toolTip = tooltip(report: report, average: temperature)
    }

    private func tooltip(report: AnomalyReport, average: Double?) -> String {
        var readings: [String] = []
        if let average { readings.append(String(format: "Avg CPU %.1f°C", average)) }
        if let hottest = watchdog.hottestCoreCelsius {
            readings.append(String(format: "hottest core %.1f°C", hottest))
        }
        return readings.isEmpty ? report.summary : readings.joined(separator: " · ") + "\n" + report.summary
    }

    // MARK: - Interaction

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseDown {
            showContextMenu(from: sender)
        } else {
            togglePopover(from: sender)
        }
    }

    private func togglePopover(from button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        Task { await watchdog.refreshNow() }
    }

    @objc private func resumeAllFrozen() {
        watchdog.resumeAllFrozen()
    }
    
    @objc private func showSettings() {
        popover.performClose(nil)
        openSettings()
    }
    
    /// Right-click fallback with no SwiftUI involved, so Quit is always reachable.
    private func showContextMenu(from button: NSStatusBarButton) {
        popover.performClose(nil)
        let menu = NSMenu()
        let summary = NSMenuItem(title: watchdog.latestReport.severity.rawValue, action: nil, keyEquivalent: "")
        summary.isEnabled = false
        menu.addItem(summary)
        menu.addItem(.separator())
        let frozenCount = watchdog.frozenSwarms.count
        if frozenCount > 0 || !watchdog.frozenPIDs.isEmpty {
            let resume = NSMenuItem(
                title: frozenCount > 0 ? "Resume All Frozen (\(frozenCount))" : "Resume All Frozen",
                action: #selector(resumeAllFrozen),
                keyEquivalent: ""
            )
            resume.target = self
            menu.addItem(resume)
            menu.addItem(.separator())
        }
        let settings = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let quit = NSMenuItem(title: "Quit Firebreak", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }
}
