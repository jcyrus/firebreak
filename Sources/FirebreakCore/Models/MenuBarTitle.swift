import Foundation

/// Builds the text shown next to the menu bar icon. Pure so every state can be unit tested.
public enum MenuBarTitle {
    public static func make(
        temperatureCelsius: Double?,
        showTemperature: Bool,
        report: AnomalyReport,
        showCPU: Bool
    ) -> String {
        var parts: [String] = []
        if showTemperature, let temp = temperatureCelsius {
            parts.append(String(format: "%.0f°", temp))
        }
        if report.isTripped && showCPU {
            if let culprit = report.culpritSwarm {
                // Round to 10% steps so the badge width doesn't jitter every tick.
                let rounded = (culprit.totalCPUPercent / 10.0).rounded() * 10.0
                parts.append(String(format: "%.0f%%", rounded))
            } else {
                parts.append("WARN")
            }
        }
        return parts.isEmpty ? "" : " " + parts.joined(separator: " · ")
    }
}
