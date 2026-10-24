import Foundation

public final class SwarmAggregator: Sendable {
    public init() {}
    
    public func aggregate(processes: [ProcessNode]) -> [ProcessSwarm] {
        var buckets: [String: (displayName: String, category: ProcessSwarm.SwarmCategory, items: [ProcessNode])] = [:]
        
        let ppidMap: [Int32: Int32] = Dictionary(uniqueKeysWithValues: processes.map { ($0.pid, $0.ppid) })
        let nameMap: [Int32: String] = Dictionary(uniqueKeysWithValues: processes.map { ($0.pid, $0.name) })
        
        for proc in processes {
            let keyAndMeta = classify(proc: proc, ppidMap: ppidMap, nameMap: nameMap)
            let key = keyAndMeta.key
            
            if buckets[key] == nil {
                buckets[key] = (keyAndMeta.displayName, keyAndMeta.category, [proc])
            } else {
                buckets[key]?.items.append(proc)
            }
        }
        
        let swarms = buckets.map { (key, val) in
            ProcessSwarm(
                groupKey: key,
                displayName: val.displayName,
                category: val.category,
                processes: val.items
            )
        }
        
        return swarms.sorted { $0.totalCPUPercent > $1.totalCPUPercent }
    }
    
    private func classify(
        proc: ProcessNode,
        ppidMap: [Int32: Int32],
        nameMap: [Int32: String]
    ) -> (key: String, displayName: String, category: ProcessSwarm.SwarmCategory) {
        let p = proc.path
        let n = proc.name
        
        // 1. CoreSimulator / Simulator Extensions
        if p.contains("CoreSimulator") || p.contains(".simruntime") || n.contains("launchd_sim") || p.contains("Poster.appex") || p.contains("PosterApp") {
            return ("coresimulator", "iOS Simulator Runtime", .simulator)
        }
        
        // 2. OrbStack / Containers
        if p.contains("OrbStack") || n.contains("docker") || n.contains("containerd") {
            return ("orbstack", "OrbStack / Containers", .container)
        }
        
        // 3. Browsers & Electron
        if p.contains("Google Chrome") || n.contains("Google Chrome") {
            return ("chrome", "Google Chrome", .browser)
        }
        if p.contains("Zen.app") || n.contains("zen") {
            return ("zen", "Zen Browser", .browser)
        }
        if p.contains("Safari.app") || n.contains("com.apple.WebKit") {
            return ("safari", "Safari Engine", .browser)
        }
        if p.contains("Ghostty.app") || n.contains("ghostty") {
            return ("ghostty", "Ghostty Terminal", .app)
        }
        if p.contains("LarkSuite.app") || n.contains("Lark") {
            return ("lark", "Lark Suite", .app)
        }
        
        // 4. Compilers / Build Systems
        if n == "swift-frontend" || n == "swiftc" || n == "rustc" || n == "cargo" || n == "clang" || n == "xcrun" {
            return ("build_tools", "Compiler & Build Tools", .buildTool)
        }
        
        // 5. Parent grouping fallback
        if let parentName = nameMap[proc.ppid], proc.ppid > 1 {
            return ("parent_\(proc.ppid)", "\(parentName) (Child Group)", .app)
        }
        
        // 6. Standalone process
        return ("proc_\(proc.pid)", n.isEmpty ? "PID \(proc.pid)" : n, .system)
    }
}
