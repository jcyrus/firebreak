import Foundation
import UserNotifications

/// Posts thermal anomaly alerts.
///
/// `UNUserNotificationCenter` throws `NSInternalInconsistencyException` when the
/// process is not running from a real `.app` bundle (e.g. `swift run FirebreakApp`).
/// In that case we fall back to a plain `osascript` banner without action buttons.
public final class ThermalNotificationManager: NSObject, @unchecked Sendable, UNUserNotificationCenterDelegate {
    public static let shared = ThermalNotificationManager()
    
    public static let categoryThermalAnomaly = "FIREBREAK_THERMAL_ANOMALY"
    public static let actionShutdownSimulator = "ACTION_SHUTDOWN_SIMULATOR"
    public static let actionFreezeSwarm = "ACTION_FREEZE_SWARM"
    public static let actionKillSwarm = "ACTION_KILL_SWARM"
    
    /// True only when running from a bundled `.app` with a bundle identifier.
    public static var isRunningInAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
    }
    
    private var center: UNUserNotificationCenter?
    private var lastNotifiedTime: [String: Date] = [:]
    private let cooldownInterval: TimeInterval = 60.0 // Minimum 60s cooldown per swarm
    private let lock = NSLock()
    
    /// Swarms pending action from a notification, keyed by group key.
    private var pendingSwarms: [String: ProcessSwarm] = [:]
    
    public override init() {
        super.init()
        if Self.isRunningInAppBundle {
            let c = UNUserNotificationCenter.current()
            c.delegate = self
            center = c
            setupCategories()
        }
    }
    
    public func requestPermissions() async -> Bool {
        guard let center else { return false }
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }
    
    private func setupCategories() {
        guard let center else { return }
        
        let shutdownAction = UNNotificationAction(
            identifier: Self.actionShutdownSimulator,
            title: "Shutdown Simulators",
            options: []
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
        
        let now = Date()
        lock.lock()
        if let last = lastNotifiedTime[culprit.groupKey], now.timeIntervalSince(last) < cooldownInterval {
            lock.unlock()
            return
        }
        lastNotifiedTime[culprit.groupKey] = now
        pendingSwarms[culprit.groupKey] = culprit
        lock.unlock()
        
        let title = report.severity == .critical
            ? "🔥 Thermal Critical: \(culprit.displayName)"
            : "⚠️ High Thermal Load: \(culprit.displayName)"
        let subtitle = "\(culprit.processCount) processes consuming \(String(format: "%.1f", culprit.totalCPUPercent))% CPU"
        
        guard let center else {
            postFallbackBanner(title: title, subtitle: subtitle, body: report.summary)
            return
        }
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = subtitle
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
    
    /// Plain banner via AppleScript for non-bundled runs (no action buttons).
    private func postFallbackBanner(title: String, subtitle: String, body: String) {
        func escape(_ s: String) -> String {
            s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        }
        let script = "display notification \"\(escape(body))\" with title \"\(escape(title))\" subtitle \"\(escape(subtitle))\""
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]
        try? task.run()
    }
    
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let groupKey = response.notification.request.content.userInfo["groupKey"] as? String
        lock.lock()
        let swarm = groupKey.flatMap { pendingSwarms[$0] }
        lock.unlock()
        
        let controller = ProcessController()
        
        switch response.actionIdentifier {
        case Self.actionShutdownSimulator:
            _ = DomainRecipes().shutdownAllSimulators()
        case Self.actionFreezeSwarm:
            if let swarm { controller.freeze(swarm: swarm) }
        case Self.actionKillSwarm:
            if let swarm { controller.terminate(swarm: swarm, force: true) }
        default:
            break
        }
        
        completionHandler()
    }
    
    /// Show banners even while the menu bar app is frontmost.
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
