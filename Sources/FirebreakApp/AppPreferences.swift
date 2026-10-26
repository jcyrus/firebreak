import Foundation
import Observation
import ServiceManagement
import FirebreakCore

/// App-level preferences that only affect the menu bar UI. Monitoring settings live on `WatchdogService`.
@MainActor
@Observable
final class AppPreferences {
    private static let showCPUKey = "showCPUInMenuBar"
    private static let showTemperatureKey = "showTemperatureInMenuBar"
    private let defaults: UserDefaults

    var showCPUInMenuBar: Bool {
        didSet { defaults.set(showCPUInMenuBar, forKey: Self.showCPUKey) }
    }
    
    /// On by default: the menu bar temperature is what lets Firebreak replace a separate sensor app.
    var showTemperatureInMenuBar: Bool {
        didSet { defaults.set(showTemperatureInMenuBar, forKey: Self.showTemperatureKey) }
    }

    private(set) var launchAtLoginStatus: SMAppService.Status = .notRegistered
    private(set) var launchAtLoginError: String?

    /// Login items only work from a real `.app` bundle, not `swift run`.
    var canLaunchAtLogin: Bool { ThermalNotificationManager.isRunningInAppBundle }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.showCPUInMenuBar = defaults.object(forKey: Self.showCPUKey) as? Bool ?? true
        self.showTemperatureInMenuBar = defaults.object(forKey: Self.showTemperatureKey) as? Bool ?? true
        refreshLaunchAtLoginStatus()
    }

    var launchAtLogin: Bool {
        get { launchAtLoginStatus == .enabled || launchAtLoginStatus == .requiresApproval }
        set {
            launchAtLoginError = nil
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                launchAtLoginError = error.localizedDescription
            }
            refreshLaunchAtLoginStatus()
        }
    }

    func refreshLaunchAtLoginStatus() {
        launchAtLoginStatus = canLaunchAtLogin ? SMAppService.mainApp.status : .notRegistered
    }
}
