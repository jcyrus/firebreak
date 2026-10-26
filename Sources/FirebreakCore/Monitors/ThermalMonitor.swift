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
        // The breaker trips on the same reading the menu bar shows, so what you see is what trips.
        let temp = cpuTemperatureCelsius()
        
        return ThermalStatus(
            state: state,
            temperatureCelsius: temp,
            loadAverage1Min: loadAvgs[0],
            loadAverage5Min: loadAvgs[1],
            loadAverage15Min: loadAvgs[2],
            coreCount: coreCount
        )
    }
    
    /// Average of the SMC per-core CPU sensors, the reading Stats calls "Average CPU". The HID "PMU tdie"
    /// sensors sit away from the cores and read ~10°C cooler, so they're only a fallback when the SMC
    /// can't be opened; the hottest HID sensor is used then, since even it runs below the cores.
    public func cpuTemperatureCelsius() -> Double? {
        let coreAverage = FBGetCPUCoreAverageTemperatureCelsius()
        if coreAverage > 0 { return coreAverage }
        let hidMax = FBGetMaxDieTemperatureCelsius()
        return hidMax > 0 ? hidMax : nil
    }
    
    /// Hottest single SMC CPU core sensor, shown in the menu bar tooltip.
    public func hottestCPUCoreCelsius() -> Double? {
        let hottest = FBGetCPUCoreMaxTemperatureCelsius()
        return hottest > 0 ? hottest : nil
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
