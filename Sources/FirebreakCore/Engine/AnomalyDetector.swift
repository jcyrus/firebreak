import Foundation

public struct AnomalyReport: Sendable, Codable {
    public enum Severity: String, Sendable, Codable {
        case normal = "Normal"
        case warning = "Warning (High Load / Warm)"
        case critical = "Critical (Thermal Throttling / Runaway Swarm)"
    }
    
    public enum RecommendedAction: String, Sendable, Codable {
        case none = "None"
        case shutdownSimulator = "Run 'xcrun simctl shutdown all'"
        case freezeSwarm = "Freeze Swarm (SIGSTOP)"
        case killSwarm = "Terminate Swarm (SIGKILL)"
    }
    
    public let severity: Severity
    public let culpritSwarm: ProcessSwarm?
    public let summary: String
    public let recommendedAction: RecommendedAction
    public let timestamp: Date
    
    public init(
        severity: Severity,
        culpritSwarm: ProcessSwarm?,
        summary: String,
        recommendedAction: RecommendedAction,
        timestamp: Date = Date()
    ) {
        self.severity = severity
        self.culpritSwarm = culpritSwarm
        self.summary = summary
        self.recommendedAction = recommendedAction
        self.timestamp = timestamp
    }
    
    public var isTripped: Bool {
        severity != .normal
    }
}

public final class AnomalyDetector: Sendable {
    public let temperatureThresholdCelsius: Double
    
    public init(temperatureThresholdCelsius: Double = 85.0) {
        self.temperatureThresholdCelsius = temperatureThresholdCelsius
    }
    
    public func analyze(thermal: ThermalStatus, swarms: [ProcessSwarm]) -> AnomalyReport {
        let topSwarm = swarms.first
        let topCPU = topSwarm?.totalCPUPercent ?? 0.0
        let topCount = topSwarm?.processCount ?? 0
        let topName = topSwarm?.displayName ?? "Unknown"
        let isSim = topSwarm?.category == .simulator
        
        // 1. Primary Hardware Temperature Trip (>= 65°C)
        if let temp = thermal.temperatureCelsius, temp >= temperatureThresholdCelsius {
            let action: AnomalyReport.RecommendedAction = isSim ? .shutdownSimulator : .freezeSwarm
            let summary = "🔥 THERMAL TRIP: Hardware temperature reached \(String(format: "%.1f", temp))°C (threshold: \(String(format: "%.0f", temperatureThresholdCelsius))°C). Top swarm: \(topName) (\(String(format: "%.1f", topCPU))% CPU across \(topCount) processes)."
            return AnomalyReport(
                severity: .critical,
                culpritSwarm: topSwarm,
                summary: summary,
                recommendedAction: action
            )
        }
        
        // 2. Critical condition: Native thermal state is serious/critical OR load average is severely saturated
        if thermal.state.isElevated || (thermal.loadAverage1Min > Double(thermal.coreCount) * 2.0 && topCPU > 200.0) {
            let action: AnomalyReport.RecommendedAction = isSim ? .shutdownSimulator : .killSwarm
            let summary = "🔥 CRITICAL: \(topName) is consuming \(String(format: "%.1f", topCPU))% CPU across \(topCount) processes while system load is \(String(format: "%.2f", thermal.loadAverage1Min))."
            return AnomalyReport(
                severity: .critical,
                culpritSwarm: topSwarm,
                summary: summary,
                recommendedAction: action
            )
        }
        
        // 2. Warning condition: Single swarm consuming excessive multi-core CPU or high process count runaway
        if topSwarm?.isSwarmAnomaly == true {
            let action: AnomalyReport.RecommendedAction = isSim ? .shutdownSimulator : .freezeSwarm
            let summary = "⚠️ WARNING: Elevated activity detected in \(topName) (\(String(format: "%.1f", topCPU))% CPU across \(topCount) processes)."
            return AnomalyReport(
                severity: .warning,
                culpritSwarm: topSwarm,
                summary: summary,
                recommendedAction: action
            )
        }
        
        return AnomalyReport(
            severity: .normal,
            culpritSwarm: nil,
            summary: "All systems nominal. Thermal state: \(thermal.state.rawValue).",
            recommendedAction: .none
        )
    }
}
