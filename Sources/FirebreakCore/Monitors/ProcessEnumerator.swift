import Foundation
import Darwin

public final class ProcessEnumerator: @unchecked Sendable {
    private struct RawProcessSample {
        let pid: Int32
        let ppid: Int32
        let name: String
        let path: String
        let totalTimeNs: UInt64
        let residentBytes: UInt64
    }
    
    public init() {}
    
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
            
            let nameWithMirror = Mirror(reflecting: bsdInfo.pbi_name)
            let nameChars = nameWithMirror.children.compactMap { $0.value as? CChar }
            let name = nameChars.withUnsafeBufferPointer { ptr in
                ptr.baseAddress.map { String(cString: $0) } ?? ""
            }
            
            var pathBuffer = [CChar](repeating: 0, count: 4096)
            var fullPath = ""
            if proc_pidpath(pid, &pathBuffer, 4096) > 0 {
                fullPath = pathBuffer.withUnsafeBufferPointer { ptr in
                    ptr.baseAddress.map { String(cString: $0) } ?? ""
                }
            }
            
            map[pid] = RawProcessSample(
                pid: pid,
                ppid: Int32(bsdInfo.pbi_ppid),
                name: name,
                path: fullPath,
                totalTimeNs: totalTime,
                residentBytes: residentBytes
            )
        }
        
        return map
    }
    
    public func snapshot(sampleInterval: TimeInterval = 0.3) async -> [ProcessNode] {
        let firstSamples = collectRawSamples()
        let intervalUs = UInt32(max(0.1, sampleInterval) * 1_000_000)
        usleep(intervalUs)
        let secondSamples = collectRawSamples()
        
        var nodes: [ProcessNode] = []
        let durationNs = Double(intervalUs) * 1_000.0
        
        for (pid, second) in secondSamples {
            var cpuPct = 0.0
            if let first = firstSamples[pid] {
                if second.totalTimeNs >= first.totalTimeNs {
                    let diffNs = Double(second.totalTimeNs - first.totalTimeNs)
                    cpuPct = (diffNs / durationNs) * 100.0
                }
            }
            
            nodes.append(ProcessNode(
                pid: pid,
                ppid: second.ppid,
                name: second.name,
                path: second.path,
                cpuPercent: cpuPct,
                residentMemoryBytes: second.residentBytes
            ))
        }
        
        return nodes
    }
}
