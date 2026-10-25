import Foundation
import UserNotifications

public final class ThermalNotificationManager: NSObject, @unchecked Sendable, UNUserNotificationCenterDelegate {
    public static let shared = ThermalNotificationManager()
    
    public static let categoryThermalAnomaly = "FIREBREAK_THERMAL_ANOMALY"
    public static let actionShutdownSimulator = "ACTION_SHUTDOWN_SIMULATOR"
    public static let actionFreezeSwarm = "ACTION_FREEZE_SWARM"
    public static let actionKillSwarm = "ACTION_KILL_SWARM"
    
    private let center = UNUserNotificationCenter.current()
    private var lastNotifiedTime: [String: Date] = [:]
    private let cooldownInterval: TimeInterval = 60.0 // Minimum 60s cooldown per swarm
    
    public override init() {
        super.init()
        center.delegate = self
        setupCategories()
    }
    
    public func requestPermissions() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }
    
    private func setupCategories() {
        let shutdownAction = UNNotificationAction(
            identifier: Self.actionShutdownSimulator,
            title: "Shutdown Simulators",
            options: [.foreground]
        )
        
        let freezeAction = UNNotificationAction(
            identifier: Self.actionFreezeSwarm,
            title: "Freeze Swarm (SIGSTOP)",
            options: []
        )
        
        let killAction = UNNotificationAction(
            identifier: Self.actionKillSwarm,
            title: "Terminate Swarm (SIGKILL)",
            options: [.destructive]
        )
        
        let anomalyCategory = UNNotificationCategory(
            identifier: Self.categoryThermalAnomaly,
            actions: [shutdownAction, freezeAction, killAction],
            intentIdentifiers: [],
            options: []
        )
        
        center.setNotificationCategories([anomalyCategory])
    }
    
    public func postAlert(for report: AnomalyReport) {
        guard report.isTripped, let culprit = report.culpritSwarm else { return }
        
        // Cooldown check
        let now = Date()
        if let last = lastNotifiedTime[culprit.groupKey], now.timeIntervalSince(last) < cooldownInterval {
            return
        }
        lastNotifiedTime[culprit.groupKey] = now
        
        let content = UNMutableNotificationContent()
        content.title = report.severity == .critical ? "🔥 Thermal Critical: \(culprit.displayName)" : "⚠️ High Thermal Load: \(culprit.displayName)"
        content.subtitle = "\(culprit.processCount) processes consuming \(String(format: "%.1f", culprit.totalCPUPercent))% CPU"
        content.body = report.summary
        content.sound = report.severity == .critical ? .defaultCritical : .default
        content.categoryIdentifier = Self.categoryThermalAnomaly
        content.userInfo = ["groupKey": culprit.groupKey]
        
        let request = UNNotificationRequest(
            identifier: "firebreak-\(culprit.groupKey)-\(Int(now.timeIntervalSince1970))",
            content: content,
            trigger: nil
        )
        
        center.add(request) { _ in }
    }
    
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let action = response.actionIdentifier
        let recipes = DomainRecipes()
        
        switch action {
        case Self.actionShutdownSimulator:
            _ = recipes.shutdownAllSimulators()
        default:
            break
        }
        
        completionHandler()
    }
}
