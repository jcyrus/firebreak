import Foundation
import Observation

@Observable
public final class WatchdogService: @unchecked Sendable {
    public private(set) var currentThermal: ThermalStatus
    public private(set) var activeSwarms: [ProcessSwarm] = []
    public private(set) var latestReport: AnomalyReport
    public private(set) var isMonitoring: Bool = false
    public var autoAlertEnabled: Bool = true
    
    private let thermalMonitor = ThermalMonitor()
    private let processEnumerator = ProcessEnumerator()
    private let aggregator = SwarmAggregator()
    private let detector = AnomalyDetector()
    private let controller = ProcessController()
    private let recipes = DomainRecipes()
    private let notificationManager = ThermalNotificationManager.shared
    
    private var monitorTask: Task<Void, Never>?
    
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
    
    public func startMonitoring(interval: TimeInterval = 3.0) {
        guard !isMonitoring else { return }
        isMonitoring = true
        
        Task {
            _ = await notificationManager.requestPermissions()
        }
        
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { break }
                await self.tick()
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }
    
    public func stopMonitoring() {
        monitorTask?.cancel()
        monitorTask = nil
        isMonitoring = false
    }
    
    public func refreshNow() async {
        await tick()
    }
    
    private func tick() async {
        let thermal = thermalMonitor.currentStatus()
        let procs = await processEnumerator.snapshot(sampleInterval: 0.25)
        let swarms = aggregator.aggregate(processes: procs)
        let report = detector.analyze(thermal: thermal, swarms: swarms)
        
        await MainActor.run {
            self.currentThermal = thermal
            self.activeSwarms = swarms
            self.latestReport = report
            
            if self.autoAlertEnabled && report.isTripped {
                self.notificationManager.postAlert(for: report)
            }
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
