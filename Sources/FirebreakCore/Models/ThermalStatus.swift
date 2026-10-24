import Foundation

public struct ThermalStatus: Sendable, Codable {
    public enum State: String, Sendable, Codable {
        case nominal = "Nominal (Cool)"
        case fair = "Fair (Warm)"
        case serious = "Serious (Hot / Throttling Risk)"
        case critical = "Critical (Immediate Cooling Required)"
        
        public static func from(processInfoState: ProcessInfo.ThermalState) -> State {
            switch processInfoState {
            case .nominal: return .nominal
            case .fair: return .fair
            case .serious: return .serious
            case .critical: return .critical
            @unknown default: return .nominal
            }
        }
        
        public var isElevated: Bool {
            self == .serious || self == .critical
        }
    }
    
    public let state: State
    public let temperatureCelsius: Double?
    public let loadAverage1Min: Double
    public let loadAverage5Min: Double
    public let loadAverage15Min: Double
    public let coreCount: Int
    public let timestamp: Date
    
    public init(
        state: State,
        temperatureCelsius: Double?,
        loadAverage1Min: Double,
        loadAverage5Min: Double,
        loadAverage15Min: Double,
        coreCount: Int,
        timestamp: Date = Date()
    ) {
        self.state = state
        self.temperatureCelsius = temperatureCelsius
        self.loadAverage1Min = loadAverage1Min
        self.loadAverage5Min = loadAverage5Min
        self.loadAverage15Min = loadAverage15Min
        self.coreCount = coreCount
        self.timestamp = timestamp
    }
    
    public var isLoadSaturated: Bool {
        loadAverage1Min > Double(coreCount) * 1.5
    }
}
