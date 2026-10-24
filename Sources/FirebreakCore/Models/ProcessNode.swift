import Foundation

public struct ProcessNode: Sendable, Identifiable, Codable {
    public var id: Int32 { pid }
    public let pid: Int32
    public let ppid: Int32
    public let name: String
    public let path: String
    public let cpuPercent: Double
    public let residentMemoryBytes: UInt64
    
    public init(
        pid: Int32,
        ppid: Int32,
        name: String,
        path: String,
        cpuPercent: Double,
        residentMemoryBytes: UInt64
    ) {
        self.pid = pid
        self.ppid = ppid
        self.name = name
        self.path = path
        self.cpuPercent = cpuPercent
        self.residentMemoryBytes = residentMemoryBytes
    }
    
    public var isSimulatorExtension: Bool {
        path.contains("CoreSimulator") || path.contains(".simruntime") || path.contains("launchd_sim")
    }
    
    public var isElectronHelper: Bool {
        name.contains("Helper") || path.contains("Electron")
    }
}
