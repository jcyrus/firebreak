import SwiftUI
import AppKit
import FirebreakCore

@main
struct FirebreakApp: App {
    @State private var watchdog = WatchdogService()
    
    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }
    
    var body: some Scene {
        MenuBarExtra {
            MenuBarView(watchdog: watchdog)
                .onAppear {
                    watchdog.startMonitoring(interval: 3.0)
                }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: menuBarIcon)
                if watchdog.latestReport.isTripped {
                    Text(shortAlertLabel)
                        .font(.system(.caption2, design: .monospaced, weight: .bold))
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
    
    private var menuBarIcon: String {
        switch watchdog.latestReport.severity {
        case .critical:
            return "flame.fill"
        case .warning:
            return "flame.fill"
        case .normal:
            return "flame"
        }
    }
    
    private var shortAlertLabel: String {
        if let culprit = watchdog.latestReport.culpritSwarm {
            return String(format: "%.0f%%", culprit.totalCPUPercent)
        }
        return "WARN"
    }
}
