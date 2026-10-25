import SwiftUI
import FirebreakCore

public struct MenuBarView: View {
    @Bindable var watchdog: WatchdogService
    @State private var selectedSwarm: ProcessSwarm?
    
    public init(watchdog: WatchdogService) {
        self.watchdog = watchdog
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerView
            
            if watchdog.latestReport.isTripped {
                anomalyAlertBanner
            }
            
            Divider()
            
            swarmsSection
            
            Divider()
            
            emergencyActionsSection
            
            Divider()
            
            footerView
        }
        .padding(14)
        .frame(width: 380)
    }
    
    // MARK: - Header
    private var headerView: some View {
        HStack {
            Image(systemName: "flame.fill")
                .foregroundColor(statusColor)
                .font(.system(size: 16, weight: .bold))
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Firebreak")
                        .font(.headline)
                    if let temp = watchdog.currentThermal.temperatureCelsius {
                        Text(String(format: "%.1f°C", temp))
                            .font(.system(.caption, design: .monospaced, weight: .bold))
                            .foregroundColor(temp >= 65.0 ? .red : (temp >= 55.0 ? .orange : .green))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill((temp >= 65.0 ? Color.red : (temp >= 55.0 ? Color.orange : Color.green)).opacity(0.15))
                            )
                    }
                }
                Text(watchdog.currentThermal.state.rawValue)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "Load: %.2f", watchdog.currentThermal.loadAverage1Min))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(watchdog.currentThermal.isLoadSaturated ? .red : .primary)
                Text("\(watchdog.currentThermal.coreCount) cores active")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Button {
                Task { await watchdog.refreshNow() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .padding(.leading, 4)
        }
    }
    
    // MARK: - Anomaly Alert Banner
    private var anomalyAlertBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.white)
                Text(watchdog.latestReport.severity.rawValue)
                    .font(.caption.weight(.bold))
                    .foregroundColor(.white)
                Spacer()
            }
            
            Text(watchdog.latestReport.summary)
                .font(.caption)
                .foregroundColor(.white.opacity(0.95))
            
            if let culprit = watchdog.latestReport.culpritSwarm {
                HStack {
                    if culprit.category == .simulator {
                        Button("Shutdown All Simulators") {
                            _ = watchdog.shutdownSimulators()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .controlSize(.small)
                    } else {
                        Button("Freeze Swarm") {
                            watchdog.freeze(swarm: culprit)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .controlSize(.small)
                        
                        Button("Kill Swarm") {
                            watchdog.terminate(swarm: culprit, force: true)
                        }
                        .buttonStyle(.bordered)
                        .tint(.white)
                        .controlSize(.small)
                    }
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(watchdog.latestReport.severity == .critical ? Color.red.opacity(0.85) : Color.orange.opacity(0.85))
        )
    }
    
    // MARK: - Swarms Section
    private var swarmsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("ACTIVE PROCESS SWARMS")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(.secondary)
                Spacer()
                Text("CPU %")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(.secondary)
            }
            
            let topSwarms = Array(watchdog.activeSwarms.prefix(5))
            if topSwarms.isEmpty {
                Text("No active high-load swarms")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(topSwarms) { swarm in
                    swarmRow(swarm)
                }
            }
        }
    }
    
    private func swarmRow(_ swarm: ProcessSwarm) -> some View {
        HStack(spacing: 8) {
            Image(systemName: iconName(for: swarm.category))
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .frame(width: 18)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(swarm.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text("\(swarm.processCount) processes")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text(String(format: "%.1f%%", swarm.totalCPUPercent))
                .font(.system(.caption, design: .monospaced, weight: .semibold))
                .foregroundColor(cpuColor(swarm.totalCPUPercent))
            
            Menu {
                Button("Freeze (SIGSTOP)") {
                    watchdog.freeze(swarm: swarm)
                }
                Button("Resume (SIGCONT)") {
                    watchdog.thaw(swarm: swarm)
                }
                Divider()
                Button("Force Kill (SIGKILL)", role: .destructive) {
                    watchdog.terminate(swarm: swarm, force: true)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 20)
        }
        .padding(.vertical, 2)
    }
    
    // MARK: - Emergency Actions
    private var emergencyActionsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("QUICK REMEDIATION")
                .font(.caption2.weight(.bold))
                .foregroundColor(.secondary)
            
            HStack(spacing: 8) {
                Button {
                    _ = watchdog.shutdownSimulators()
                } label: {
                    Label("Shutdown Simulators", systemImage: "iphone.slash")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Button {
                    Task { await watchdog.refreshNow() }
                } label: {
                    Label("Rescan Trees", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
    
    // MARK: - Footer
    private var footerView: some View {
        HStack {
            Toggle("Auto Alert", isOn: $watchdog.autoAlertEnabled)
                .font(.caption2)
                .toggleStyle(.checkbox)
            
            Text("• \(watchdog.currentCadence.rawValue)")
                .font(.caption2)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Helpers
    private var statusColor: Color {
        switch watchdog.latestReport.severity {
        case .critical: return .red
        case .warning: return .orange
        case .normal: return .green
        }
    }
    
    private func cpuColor(_ cpu: Double) -> Color {
        if cpu > 150.0 { return .red }
        if cpu > 50.0 { return .orange }
        return .primary
    }
    
    private func iconName(for category: ProcessSwarm.SwarmCategory) -> String {
        switch category {
        case .simulator: return "iphone"
        case .container: return "shippingbox"
        case .browser: return "globe"
        case .buildTool: return "hammer"
        case .app: return "app"
        case .system: return "gearshape"
        }
    }
}
