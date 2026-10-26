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
    /// Result of the most recent freeze / thaw / kill / shutdown, shown in the menu bar popover.
    public private(set) var lastActionMessage: String?
    /// PIDs this app has frozen, so they can be resumed on quit even if they leave the swarm list.
    public private(set) var frozenPIDs: Set<Int32> = []
    /// Average CPU core temperature for the menu bar, refreshed every `sensorInterval` while
    /// `wantsLiveTemperature` is on. Same reading the breaker trips on.
    public private(set) var displayTemperatureCelsius: Double?
    /// Hottest single CPU core, refreshed alongside `displayTemperatureCelsius` (tooltip only).
    public private(set) var hottestCoreCelsius: Double?
    /// Runs the sensor-only loop. Off means no extra wakeups beyond the process scan.
    public var wantsLiveTemperature: Bool = false {
        didSet { updateSensorLoop() }
    }
    public static let sensorInterval: TimeInterval = 2.0
    
    /// Swarms with at least one stopped process, read from kernel state rather than our own
    /// bookkeeping so freezes from notifications or a previous run still show up.
    public var frozenSwarms: [ProcessSwarm] {
        activeSwarms.filter(\.isFrozen)
    }
    public var autoAlertEnabled: Bool {
        didSet { defaults.set(autoAlertEnabled, forKey: Self.autoAlertKey) }
    }
    /// Hardware temperature that trips the breaker. Alert cadence starts 5°C below it, warm cadence 15°C below.
    public var temperatureThresholdCelsius: Double {
        didSet { defaults.set(temperatureThresholdCelsius, forKey: Self.thresholdKey) }
    }
    
    /// Apple Silicon cores run 70-85°C under normal heavy load, so trip above that on the core average.
    public static let defaultThresholdCelsius: Double = 85.0
    public static let thresholdRange: ClosedRange<Double> = 60...105
    private static let autoAlertKey = "autoAlertEnabled"
    private static let thresholdKey = "temperatureThresholdCelsius"
    /// Thresholds saved before 2026-10-26 were tuned for the cooler HID die sensors; reset them once.
    private static let thresholdSensorVersionKey = "temperatureThresholdSensorVersion"
    private static let currentThresholdSensorVersion = 2
    private let defaults: UserDefaults
    
    private let thermalMonitor = ThermalMonitor()
    private let processEnumerator = ProcessEnumerator()
    private let aggregator = SwarmAggregator()
    private let controller = ProcessController()
    private let recipes = DomainRecipes()
    private let notificationManager = ThermalNotificationManager.shared
    
    private var monitorTask: Task<Void, Never>?
    private var sensorTask: Task<Void, Never>?
    private var cooldownCounter: Int = 0
    
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.autoAlertEnabled = defaults.object(forKey: Self.autoAlertKey) as? Bool ?? true
        if defaults.integer(forKey: Self.thresholdSensorVersionKey) < Self.currentThresholdSensorVersion {
            defaults.removeObject(forKey: Self.thresholdKey)
            defaults.set(Self.currentThresholdSensorVersion, forKey: Self.thresholdSensorVersionKey)
        }
        let storedThreshold = defaults.double(forKey: Self.thresholdKey)
        self.temperatureThresholdCelsius = storedThreshold > 0 ? storedThreshold : Self.defaultThresholdCelsius
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
        updateSensorLoop()
    }
    
    public func stopMonitoring() {
        monitorTask?.cancel()
        monitorTask = nil
        isMonitoring = false
        updateSensorLoop()
    }
    
    private func updateSensorLoop() {
        guard wantsLiveTemperature && isMonitoring else {
            sensorTask?.cancel()
            sensorTask = nil
            displayTemperatureCelsius = nil
            hottestCoreCelsius = nil
            return
        }
        guard sensorTask == nil else { return }
        let monitor = thermalMonitor
        sensorTask = Task(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { break }
                let temp = monitor.cpuTemperatureCelsius()
                let hottest = monitor.hottestCPUCoreCelsius()
                await MainActor.run {
                    self.displayTemperatureCelsius = temp
                    self.hottestCoreCelsius = hottest
                }
                try? await Task.sleep(nanoseconds: UInt64(Self.sensorInterval * 1_000_000_000))
            }
        }
    }
    
    public func refreshNow() async {
        _ = await tick()
    }
    
    @discardableResult
    private func tick() async -> TimeInterval {
        let (sampleWin, threshold) = await MainActor.run {
            (self.currentCadence.sampleWindow, self.temperatureThresholdCelsius)
        }
        let detector = AnomalyDetector(temperatureThresholdCelsius: threshold)
        let thermal = thermalMonitor.currentStatus()
        let procs = await processEnumerator.snapshot(sampleInterval: sampleWin)
        let swarms = aggregator.aggregate(processes: procs)
        let report = detector.analyze(thermal: thermal, swarms: swarms)
        
        // Cadence state and published properties are only touched on the main actor, so a
        // manual refresh racing the monitor loop can't corrupt the hysteresis counter.
        let nextCadence = await MainActor.run { () -> CadenceMode in
            let next = self.updateCadence(thermal: thermal, report: report, threshold: threshold)
            self.currentThermal = thermal
            self.activeSwarms = swarms
            self.latestReport = report
            self.currentCadence = next
            
            if self.autoAlertEnabled && report.isTripped {
                self.notificationManager.postAlert(for: report)
            }
            return next
        }
        
        return nextCadence.interval
    }
    
    private func updateCadence(thermal: ThermalStatus, report: AnomalyReport, threshold: Double) -> CadenceMode {
        let temp = thermal.temperatureCelsius ?? 40.0
        let isTripped = report.isTripped
        let isLoadHigh = thermal.loadAverage1Min >= Double(thermal.coreCount) * 0.75
        
        // Immediate escalation to Alert
        if temp >= threshold - 5.0 || isTripped || thermal.state.isElevated {
            cooldownCounter = 0
            return .alert
        }
        
        // Warm mode
        if temp >= threshold - 15.0 || isLoadHigh {
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
        let outcome = controller.freeze(swarm: swarm)
        frozenPIDs.formUnion(swarm.processes.filter { !ProcessController.isProtected($0) }.map(\.pid))
        lastActionMessage = "Froze \(swarm.displayName): \(outcome.summary)"
        Task { await refreshNow() }
    }
    
    public func thaw(swarm: ProcessSwarm) {
        let outcome = controller.thaw(swarm: swarm)
        frozenPIDs.subtract(swarm.processes.map(\.pid))
        lastActionMessage = "Resumed \(swarm.displayName): \(outcome.summary)"
        Task { await refreshNow() }
    }
    
    public func terminate(swarm: ProcessSwarm, force: Bool = true) {
        let outcome = controller.terminate(swarm: swarm, force: force)
        frozenPIDs.subtract(swarm.processes.map(\.pid))
        lastActionMessage = "Killed \(swarm.displayName): \(outcome.summary)"
        Task { await refreshNow() }
    }
    
    public func resumeAllFrozen() {
        let swarms = frozenSwarms
        swarms.forEach { controller.thaw(swarm: $0) }
        controller.resume(pids: frozenPIDs)
        frozenPIDs.removeAll()
        lastActionMessage = swarms.isEmpty ? "Resumed frozen processes" : "Resumed \(swarms.count) frozen swarm(s)"
        Task { await refreshNow() }
    }
    
    /// Called on app termination: never leave processes stopped with no UI left to resume them.
    public func resumeFrozenOnQuit() {
        controller.resume(pids: frozenPIDs)
        frozenPIDs.removeAll()
    }
    
    /// Runs `xcrun simctl shutdown all` off the main thread; it can take several seconds under load.
    @discardableResult
    public func shutdownSimulators() async -> (exitCode: Int32, output: String) {
        await MainActor.run { self.lastActionMessage = "Shutting down simulators…" }
        let recipes = self.recipes
        let res = await Task.detached(priority: .userInitiated) {
            recipes.shutdownAllSimulators()
        }.value
        await MainActor.run {
            self.lastActionMessage = res.exitCode == 0
                ? "Simulators shut down"
                : "simctl failed (exit \(res.exitCode))"
        }
        await refreshNow()
        return res
    }
}
