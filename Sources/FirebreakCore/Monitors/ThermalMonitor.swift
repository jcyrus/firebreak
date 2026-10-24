import Foundation
import Darwin

public final class ThermalMonitor: Sendable {
    public init() {}
    
    public func currentStatus() -> ThermalStatus {
        let thermalState = ProcessInfo.processInfo.thermalState
        let state = ThermalStatus.State.from(processInfoState: thermalState)
        
        var loadAvgs = [Double](repeating: 0.0, count: 3)
        getloadavg(&loadAvgs, 3)
        
        let coreCount = ProcessInfo.processInfo.activeProcessorCount
        
        return ThermalStatus(
            state: state,
            temperatureCelsius: nil,
            loadAverage1Min: loadAvgs[0],
            loadAverage5Min: loadAvgs[1],
            loadAverage15Min: loadAvgs[2],
            coreCount: coreCount
        )
    }
}
