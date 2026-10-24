import Testing
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
}
