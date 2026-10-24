import Foundation
import FirebreakCore

@main
struct FirebreakCLI {
    static func main() async {
        let args = CommandLine.arguments.dropFirst()
        let command = args.first ?? "status"
        
        let thermalMonitor = ThermalMonitor()
        let processEnumerator = ProcessEnumerator()
        let aggregator = SwarmAggregator()
        let detector = AnomalyDetector()
        let recipes = DomainRecipes()
        
        switch command {
        case "status":
            printHeader()
            let thermal = thermalMonitor.currentStatus()
            printThermal(thermal)
            
            print("\nSampling active process swarms (300ms)...")
            let procs = await processEnumerator.snapshot()
            let swarms = aggregator.aggregate(processes: procs)
            printTopSwarms(swarms.prefix(6))
            
            let report = detector.analyze(thermal: thermal, swarms: swarms)
            print("\n[Circuit Breaker]")
            print("Status: \(report.severity.rawValue)")
            print("Diagnosis: \(report.summary)")
            if report.recommendedAction != .none {
                print("Recommended Action: \(report.recommendedAction.rawValue)")
            }
            
        case "scan":
            printHeader()
            print("Scanning all process swarms...")
            let procs = await processEnumerator.snapshot()
            let swarms = aggregator.aggregate(processes: procs)
            printTopSwarms(swarms.filter { $0.totalCPUPercent > 1.0 || $0.processCount > 1 }.prefix(15))
            
        case "trip":
            let thermal = thermalMonitor.currentStatus()
            let procs = await processEnumerator.snapshot()
            let swarms = aggregator.aggregate(processes: procs)
            let report = detector.analyze(thermal: thermal, swarms: swarms)
            
            if report.isTripped {
                print("TRIPPED: \(report.severity.rawValue)")
                print(report.summary)
                print("Action: \(report.recommendedAction.rawValue)")
                exit(1)
            } else {
                print("NOMINAL: Thermal state \(thermal.state.rawValue), load \(String(format: "%.2f", thermal.loadAverage1Min))")
                exit(0)
            }
            
        case "cool":
            print("Executing emergency cooling recipe...")
            let res = recipes.shutdownAllSimulators()
            print("simctl shutdown all -> exit \(res.exitCode)")
            if !res.output.isEmpty {
                print(res.output)
            }
            print("Cooling commands dispatched.")
            
        case "help", "--help", "-h":
            print("""
            🔥 Firebreak — Native macOS Thermal & Swarm Circuit Breaker
            
            Usage:
              firebreak status   Show thermal state, load, and top process swarms
              firebreak scan     List all active multi-process clusters & trees
              firebreak trip     Run anomaly detection (exit 1 if circuit tripped)
              firebreak cool     Run emergency remediation recipes (e.g. shutdown simulators)
            """)
            
        default:
            print("Unknown command: '\(command)'. Run 'firebreak help' for usage.")
            exit(1)
        }
    }
    
    private static func printHeader() {
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("  🔥 FIREBREAK — macOS Thermal Circuit Breaker")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }
    
    private static func printThermal(_ t: ThermalStatus) {
        let loadStr = String(format: "%.2f / %.2f / %.2f (%d cores)", t.loadAverage1Min, t.loadAverage5Min, t.loadAverage15Min, t.coreCount)
        print("Thermal State : \(t.state.rawValue)")
        print("Load Averages : \(loadStr)")
    }
    
    private static func pad(_ s: String, _ length: Int) -> String {
        if s.count >= length {
            return String(s.prefix(length))
        }
        return s.padding(toLength: length, withPad: " ", startingAt: 0)
    }

    private static func printTopSwarms(_ swarms: any Sequence<ProcessSwarm>) {
        print("\nTop Active Process Swarms:")
        print("  \(pad("SWARM / GROUP", 30)) \(pad("TOTAL CPU", 12)) \(pad("COUNT", 10)) \(pad("CATEGORY", 20))")
        print("  -------------------------------------------------------------------------------")
        for s in swarms {
            let cpuStr = String(format: "%.1f%%", s.totalCPUPercent)
            let countStr = "\(s.processCount) pids"
            let catStr = s.category.rawValue
            print("  \(pad(s.displayName, 30)) \(pad(cpuStr, 12)) \(pad(countStr, 10)) \(pad(catStr, 20))")
        }
    }
}
