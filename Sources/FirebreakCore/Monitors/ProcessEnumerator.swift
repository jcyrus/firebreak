import Foundation
import Darwin

public final class ProcessEnumerator: @unchecked Sendable {
    private struct RawProcessSample {
        let pid: Int32
        let ppid: Int32
        let name: String
        let path: String
        let totalTimeTicks: UInt64
        let residentBytes: UInt64
        let isStopped: Bool
    }
    
    private struct CachedProcessInfo {
        let name: String
        let path: String
        let startTime: UInt64
    }
    
    private let timebaseNumer: Double
    private let timebaseDenom: Double
    private var pathCache: [Int32: CachedProcessInfo] = [:]
    private var pruneCounter: Int = 0
    private let lock = NSLock()
    
    public init() {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        self.timebaseNumer = Double(timebase.numer)
        self.timebaseDenom = Double(timebase.denom)
    }
    
    private func collectRawSamples() -> [Int32: RawProcessSample] {
        let count = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard count > 0 else { return [:] }
        
        var pids = [Int32](repeating: 0, count: Int(count))
        let bytesWritten = proc_listpids(
            UInt32(PROC_ALL_PIDS),
            0,
            &pids,
            count * Int32(MemoryLayout<Int32>.size)
        )
        guard bytesWritten > 0 else { return [:] }
        
        var map: [Int32: RawProcessSample] = [:]
        var pathBuffer = [CChar](repeating: 0, count: 4096)
        
        lock.lock()
        defer { lock.unlock() }
        
        for pid in pids where pid > 0 {
            var bsdInfo = proc_bsdinfo()
            let bsdSize = proc_pidinfo(
                pid,
                PROC_PIDTBSDINFO,
                0,
                &bsdInfo,
                Int32(MemoryLayout<proc_bsdinfo>.size)
            )
            guard bsdSize == MemoryLayout<proc_bsdinfo>.size else { continue }
            
            var taskInfo = proc_taskinfo()
            let taskSize = proc_pidinfo(
                pid,
                PROC_PIDTASKINFO,
                0,
                &taskInfo,
                Int32(MemoryLayout<proc_taskinfo>.size)
            )
            
            let totalTime: UInt64 = (taskSize == MemoryLayout<proc_taskinfo>.size)
                ? (taskInfo.pti_total_user + taskInfo.pti_total_system)
                : 0
            let residentBytes: UInt64 = (taskSize == MemoryLayout<proc_taskinfo>.size)
                ? taskInfo.pti_resident_size
                : 0
            
            let startTime = bsdInfo.pbi_start_tvsec
            let cached = pathCache[pid]
            let name: String
            let fullPath: String
            
            if let cached = cached, cached.startTime == startTime {
                name = cached.name
                fullPath = cached.path
            } else {
                let nameWithMirror = Mirror(reflecting: bsdInfo.pbi_name)
                let nameChars = nameWithMirror.children.compactMap { $0.value as? CChar }
                name = nameChars.withUnsafeBufferPointer { ptr in
                    ptr.baseAddress.map { String(cString: $0) } ?? ""
                }
                
                var path = ""
                if proc_pidpath(pid, &pathBuffer, 4096) > 0 {
                    path = pathBuffer.withUnsafeBufferPointer { ptr in
                        ptr.baseAddress.map { String(cString: $0) } ?? ""
                    }
                }
                fullPath = path
                pathCache[pid] = CachedProcessInfo(name: name, path: fullPath, startTime: startTime)
            }
            
            map[pid] = RawProcessSample(
                pid: pid,
                ppid: Int32(bsdInfo.pbi_ppid),
                name: name,
                path: fullPath,
                totalTimeTicks: totalTime,
                residentBytes: residentBytes,
                isStopped: bsdInfo.pbi_status == UInt32(SSTOP)
            )
        }
        
        pruneCounter += 1
        if pruneCounter >= 10 {
            pruneCounter = 0
            let activePidSet = Set(pids)
            pathCache = pathCache.filter { activePidSet.contains($0.key) }
        }
        
        return map
    }
    
    public func snapshot(sampleInterval: TimeInterval = 0.3) async -> [ProcessNode] {
        let t0 = mach_absolute_time()
        let firstSamples = collectRawSamples()
        // Suspend rather than usleep so the cooperative pool thread stays free under load.
        try? await Task.sleep(nanoseconds: UInt64(max(0.1, sampleInterval) * 1_000_000_000))
        let t1 = mach_absolute_time()
        let secondSamples = collectRawSamples()
        
        var nodes: [ProcessNode] = []
        let elapsedNs = Double(t1 - t0) * timebaseNumer / timebaseDenom
        guard elapsedNs > 0 else { return [] }
        
        for (pid, second) in secondSamples {
            var cpuPct = 0.0
            if let first = firstSamples[pid] {
                if second.totalTimeTicks >= first.totalTimeTicks {
                    let diffTicks = Double(second.totalTimeTicks - first.totalTimeTicks)
                    let diffNs = diffTicks * timebaseNumer / timebaseDenom
                    cpuPct = (diffNs / elapsedNs) * 100.0
                }
            }
            
            nodes.append(ProcessNode(
                pid: pid,
                ppid: second.ppid,
                name: second.name,
                path: second.path,
                cpuPercent: cpuPct,
                residentMemoryBytes: second.residentBytes,
                isStopped: second.isStopped
            ))
        }
        
        return nodes
    }
}
