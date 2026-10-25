import Foundation
import Observation

@Observable
public final class WatchdogService: @unchecked Sendable {
    public enum CadenceMode: String, Sendable, Codable {
        case nominal = "Nominal (6.0s)"
        case warm = "Warm (3.0s)"
        case alert = "Alert (1.5s)"
        
        public var interval: TimeInterval {
            switch self {
            case .nominal: return 6.0
            case .warm: return 3.0
            case .alert: return 1.5
            }
        }
        
        public var sampleWindow: TimeInterval {
            switch self {
            case .nominal: return 0.20
            case .warm: return 0.25
            case .alert: return 0.30
            }
        }
    }
    
    public private(set) var currentThermal: ThermalStatus
    public private(set) var activeSwarms: [ProcessSwarm] = []
    public private(set) var latestReport: AnomalyReport
    public private(set) var isMonitoring: Bool = false
    public private(set) var currentCadence: CadenceMode = .nominal
    public var autoAlertEnabled: Bool = true
    
    private let thermalMonitor = ThermalMonitor()
    private let processEnumerator = ProcessEnumerator()
    private let aggregator = SwarmAggregator()
    private let detector = AnomalyDetector()
    private let controller = ProcessController()
    private let recipes = DomainRecipes()
    private let notificationManager = ThermalNotificationManager.shared
    
    private var monitorTask: Task<Void, Never>?
    private var cooldownCounter: Int = 0
    
    public init() {
        let initialThermal = thermalMonitor.currentStatus()
        self.currentThermal = initialThermal
        self.latestReport = AnomalyReport(
            severity: .normal,
            culpritSwarm: nil,
            summary: "Monitoring initializing...",
            recommendedAction: .none
        )
    }
    
    public func startMonitoring(interval: TimeInterval? = nil) {
        guard !isMonitoring else { return }
        isMonitoring = true
        
        Task {
            _ = await notificationManager.requestPermissions()
        }
        
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { break }
                let dynamicInterval = await self.tick()
                let sleepTime = interval ?? dynamicInterval
                try? await Task.sleep(nanoseconds: UInt64(sleepTime * 1_000_000_000))
            }
        }
    }
    
    public func stopMonitoring() {
        monitorTask?.cancel()
        monitorTask = nil
        isMonitoring = false
    }
    
    public func refreshNow() async {
        _ = await tick()
    }
    
    @discardableResult
    private func tick() async -> TimeInterval {
        let sampleWin = currentCadence.sampleWindow
        let thermal = thermalMonitor.currentStatus()
        let procs = await processEnumerator.snapshot(sampleInterval: sampleWin)
        let swarms = aggregator.aggregate(processes: procs)
        let report = detector.analyze(thermal: thermal, swarms: swarms)
        let nextCadence = updateCadence(thermal: thermal, report: report)
        
        await MainActor.run {
            self.currentThermal = thermal
            self.activeSwarms = swarms
            self.latestReport = report
            self.currentCadence = nextCadence
            
            if self.autoAlertEnabled && report.isTripped {
                self.notificationManager.postAlert(for: report)
            }
        }
        
        return nextCadence.interval
    }
    
    private func updateCadence(thermal: ThermalStatus, report: AnomalyReport) -> CadenceMode {
        let temp = thermal.temperatureCelsius ?? 40.0
        let isTripped = report.isTripped
        let isLoadHigh = thermal.loadAverage1Min >= Double(thermal.coreCount) * 0.75
        
        // Immediate escalation to Alert
        if temp >= 60.0 || isTripped || thermal.state.isElevated {
            cooldownCounter = 0
            return .alert
        }
        
        // Warm mode
        if temp >= 50.0 || isLoadHigh {
            cooldownCounter = 0
            return .warm
        }
        
        // Step down with hysteresis (require 2 consecutive cool ticks before stepping down)
        cooldownCounter += 1
        if currentCadence == .alert {
            return cooldownCounter >= 2 ? .warm : .alert
        } else if currentCadence == .warm {
            return cooldownCounter >= 2 ? .nominal : .warm
        } else {
            return .nominal
        }
    }
    
    public func freeze(swarm: ProcessSwarm) {
        controller.freeze(swarm: swarm)
        Task { await refreshNow() }
    }
    
    public func thaw(swarm: ProcessSwarm) {
        controller.thaw(swarm: swarm)
        Task { await refreshNow() }
    }
    
    public func terminate(swarm: ProcessSwarm, force: Bool = true) {
        controller.terminate(swarm: swarm, force: force)
        Task { await refreshNow() }
    }
    
    public func shutdownSimulators() -> (exitCode: Int32, output: String) {
        let res = recipes.shutdownAllSimulators()
        Task { await refreshNow() }
        return res
    }
}
