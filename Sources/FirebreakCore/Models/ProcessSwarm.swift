import Foundation

public struct ProcessSwarm: Sendable, Identifiable, Codable {
    public enum SwarmCategory: String, Sendable, Codable {
        case simulator = "iOS Simulator / CoreSimulator"
        case container = "Container / VM (OrbStack, Docker)"
        case browser = "Browser Engine (Chrome, Safari, Zen)"
        case buildTool = "Compiler / Build Tool (Swift, Rust, Clang)"
        case app = "Application"
        case system = "System Daemon"
    }
    
    public var id: String { groupKey }
    public let groupKey: String
    public let displayName: String
    public let category: SwarmCategory
    public let processes: [ProcessNode]
    public let totalCPUPercent: Double
    public let totalMemoryBytes: UInt64
    
    public init(
        groupKey: String,
        displayName: String,
        category: SwarmCategory,
        processes: [ProcessNode]
    ) {
        self.groupKey = groupKey
        self.displayName = displayName
        self.category = category
        self.processes = processes
        self.totalCPUPercent = processes.reduce(0.0) { $0 + $1.cpuPercent }
        self.totalMemoryBytes = processes.reduce(0) { $0 + $1.residentMemoryBytes }
    }
    
    public var processCount: Int {
        processes.count
    }
    
    public var isSwarmAnomaly: Bool {
        // Either multi-process swarm taking > 150% CPU, or more than 10 child processes pinned
        (totalCPUPercent > 120.0 && processCount >= 3) || totalCPUPercent > 250.0 || processCount >= 20
    }
}
