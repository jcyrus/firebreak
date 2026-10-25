import Foundation
import Darwin
import FirebreakNative

public final class ThermalMonitor: Sendable {
    public init() {}
    
    public func currentStatus() -> ThermalStatus {
        let thermalState = ProcessInfo.processInfo.thermalState
        let state = ThermalStatus.State.from(processInfoState: thermalState)
        
        var loadAvgs = [Double](repeating: 0.0, count: 3)
        getloadavg(&loadAvgs, 3)
        
        let coreCount = ProcessInfo.processInfo.activeProcessorCount
        let maxDieTemp = FBGetMaxDieTemperatureCelsius()
        let temp: Double? = maxDieTemp > 0.0 ? maxDieTemp : nil
        
        return ThermalStatus(
            state: state,
            temperatureCelsius: temp,
            loadAverage1Min: loadAvgs[0],
            loadAverage5Min: loadAvgs[1],
            loadAverage15Min: loadAvgs[2],
            coreCount: coreCount
        )
    }
    
    public func readHardwareSensors() -> [String: Double] {
        let raw = FBReadHardwareSensors()
        var result: [String: Double] = [:]
        for (k, v) in raw {
            result[k] = v.doubleValue
        }
        return result
    }
}
