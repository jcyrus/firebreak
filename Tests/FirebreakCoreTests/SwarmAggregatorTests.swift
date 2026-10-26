import Testing
import Foundation
@testable import FirebreakCore

@Suite("FirebreakCore Tests")
struct FirebreakCoreTests {
    @Test("SwarmAggregator groups simulator extensions correctly")
    func testSimulatorGrouping() {
        let procs = [
            ProcessNode(pid: 101, ppid: 1, name: "launchd_sim", path: "/Users/user/Library/Developer/CoreSimulator/launchd_sim", cpuPercent: 80.0, residentMemoryBytes: 1024),
            ProcessNode(pid: 102, ppid: 101, name: "KaleidoscopePoster", path: "/Developer/CoreSimulator/KaleidoscopePoster.appex/KaleidoscopePoster", cpuPercent: 99.0, residentMemoryBytes: 2048),
            ProcessNode(pid: 103, ppid: 101, name: "AegirPoster", path: "/Developer/CoreSimulator/AegirPoster.appex/AegirPoster", cpuPercent: 101.0, residentMemoryBytes: 2048),
            ProcessNode(pid: 201, ppid: 1, name: "WindowServer", path: "/System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer", cpuPercent: 20.0, residentMemoryBytes: 4096)
        ]
        
        let aggregator = SwarmAggregator()
        let swarms = aggregator.aggregate(processes: procs)
        
        let simSwarm = swarms.first { $0.groupKey == "coresimulator" }
        #expect(simSwarm != nil)
        #expect(simSwarm?.processCount == 3)
        #expect((simSwarm?.totalCPUPercent ?? 0.0) > 270.0)
    }
    
    @Test("AnomalyDetector trips on simulator runaway swarm")
    func testAnomalyDetector() {
        let procs = [
            ProcessNode(pid: 101, ppid: 1, name: "launchd_sim", path: "/CoreSimulator/launchd_sim", cpuPercent: 95.0, residentMemoryBytes: 1024),
            ProcessNode(pid: 102, ppid: 101, name: "KaleidoscopePoster", path: "/CoreSimulator/Poster.appex", cpuPercent: 100.0, residentMemoryBytes: 2048),
            ProcessNode(pid: 103, ppid: 101, name: "WeatherPoster", path: "/CoreSimulator/Poster.appex", cpuPercent: 90.0, residentMemoryBytes: 2048)
        ]
        
        let aggregator = SwarmAggregator()
        let swarms = aggregator.aggregate(processes: procs)
        
        let thermal = ThermalStatus(
            state: .serious,
            temperatureCelsius: 98.0,
            loadAverage1Min: 45.0,
            loadAverage5Min: 30.0,
            loadAverage15Min: 20.0,
            coreCount: 8
        )
        
        let detector = AnomalyDetector()
        let report = detector.analyze(thermal: thermal, swarms: swarms)
        
        #expect(report.isTripped == true)
        #expect(report.severity == .critical)
        #expect(report.recommendedAction == .shutdownSimulator)
    }
    
    @Test("ProcessEnumerator path cache reuses lookups cleanly")
    func testProcessEnumeratorCaching() async {
        let enumerator = ProcessEnumerator()
        let sample1 = await enumerator.snapshot(sampleInterval: 0.05)
        #expect(!sample1.isEmpty)
        
        let sample2 = await enumerator.snapshot(sampleInterval: 0.05)
        #expect(!sample2.isEmpty)
    }
    
    @Test("WatchdogService CadenceMode intervals are correctly configured")
    func testCadenceModeIntervals() {
        #expect(WatchdogService.CadenceMode.nominal.interval == 6.0)
        #expect(WatchdogService.CadenceMode.warm.interval == 3.0)
        #expect(WatchdogService.CadenceMode.alert.interval == 1.5)
    }
    
    @Test("Freeze is detected as stopped and thaw resumes only stopped processes")
    func testFreezeThawRoundTrip() async throws {
        let sleeper = Process()
        sleeper.executableURL = URL(fileURLWithPath: "/bin/sleep")
        sleeper.arguments = ["30"]
        try sleeper.run()
        defer { sleeper.terminate() }
        
        let pid = sleeper.processIdentifier
        let node = ProcessNode(pid: pid, ppid: getpid(), name: "sleep", path: "/bin/sleep", cpuPercent: 0, residentMemoryBytes: 0)
        let swarm = ProcessSwarm(groupKey: "test_sleep", displayName: "sleep", category: .app, processes: [node])
        let controller = ProcessController()
        let enumerator = ProcessEnumerator()
        
        #expect(controller.freeze(swarm: swarm).delivered == 1)
        let frozen = await enumerator.snapshot(sampleInterval: 0.05).first { $0.pid == pid }
        #expect(frozen?.isStopped == true)
        
        let frozenSwarm = ProcessSwarm(groupKey: "test_sleep", displayName: "sleep", category: .app, processes: [try #require(frozen)])
        #expect(frozenSwarm.isFrozen)
        #expect(controller.thaw(swarm: frozenSwarm).delivered == 1)
        
        let resumed = await enumerator.snapshot(sampleInterval: 0.05).first { $0.pid == pid }
        #expect(resumed?.isStopped == false)
    }
    
    @Test("Protected processes and self are never signaled")
    func testProtectedProcessesSkipped() {
        let selfNode = ProcessNode(pid: getpid(), ppid: 1, name: "xctest", path: "", cpuPercent: 0, residentMemoryBytes: 0)
        let dock = ProcessNode(pid: 999_999, ppid: 1, name: "Dock", path: "", cpuPercent: 0, residentMemoryBytes: 0)
        let swarm = ProcessSwarm(groupKey: "protected", displayName: "protected", category: .system, processes: [selfNode, dock])
        let outcome = ProcessController().freeze(swarm: swarm)
        #expect(outcome.skipped == 2)
        #expect(outcome.delivered == 0)
    }
    
    @Test("Menu bar title covers normal, tripped, no-sensor and disabled states")
    func testMenuBarTitle() {
        let normal = AnomalyReport(severity: .normal, culpritSwarm: nil, summary: "", recommendedAction: .none)
        let hog = ProcessNode(pid: 500, ppid: 1, name: "hog", path: "", cpuPercent: 238, residentMemoryBytes: 0)
        let culprit = ProcessSwarm(groupKey: "hog", displayName: "hog", category: .app, processes: [hog])
        let tripped = AnomalyReport(severity: .critical, culpritSwarm: culprit, summary: "", recommendedAction: .killSwarm)
        
        #expect(MenuBarTitle.make(temperatureCelsius: 55.6, showTemperature: true, report: normal, showCPU: true) == " 56°")
        #expect(MenuBarTitle.make(temperatureCelsius: 71.2, showTemperature: true, report: tripped, showCPU: true) == " 71° · 240%")
        #expect(MenuBarTitle.make(temperatureCelsius: 71.2, showTemperature: true, report: tripped, showCPU: false) == " 71°")
        #expect(MenuBarTitle.make(temperatureCelsius: nil, showTemperature: true, report: tripped, showCPU: true) == " 240%")
        #expect(MenuBarTitle.make(temperatureCelsius: nil, showTemperature: true, report: normal, showCPU: true) == "")
        #expect(MenuBarTitle.make(temperatureCelsius: 55.6, showTemperature: false, report: normal, showCPU: true) == "")
    }
    
    @Test("CPU core temperature reads a plausible value on hardware with sensors")
    func testAverageDieTemperature() {
        let monitor = ThermalMonitor()
        guard let hottest = monitor.currentStatus().temperatureCelsius else { return }
        let average = monitor.cpuTemperatureCelsius()
        #expect(average != nil)
        if let average {
            #expect(average > 15 && average < 120)
            #expect(abs(average - hottest) < 10)
        }
        if let core = monitor.hottestCPUCoreCelsius(), let average {
            #expect(core >= average)
        }
    }
}
