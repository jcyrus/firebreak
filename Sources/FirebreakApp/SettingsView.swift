import SwiftUI
import ServiceManagement
import FirebreakCore

struct SettingsView: View {
    @Bindable var watchdog: WatchdogService
    @Bindable var preferences: AppPreferences

    var body: some View {
        TabView {
            GeneralSettingsTab(watchdog: watchdog, preferences: preferences)
                .tabItem { Label("General", systemImage: "gearshape") }
            MonitoringSettingsTab(watchdog: watchdog)
                .tabItem { Label("Monitoring", systemImage: "thermometer.medium") }
            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 480, height: 400)
    }
}

// MARK: - General

private struct GeneralSettingsTab: View {
    let watchdog: WatchdogService
    @Bindable var preferences: AppPreferences
    
    private var hasTemperatureSensor: Bool {
        watchdog.currentThermal.temperatureCelsius != nil
    }

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $preferences.launchAtLogin)
                    .disabled(!preferences.canLaunchAtLogin)

                if !preferences.canLaunchAtLogin {
                    Text("Available when running the bundled Firebreak.app.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if preferences.launchAtLoginStatus == .requiresApproval {
                    HStack {
                        Text("Approve Firebreak in Login Items to finish enabling.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Open Login Items") {
                            SMAppService.openSystemSettingsLoginItems()
                        }
                        .controlSize(.small)
                    }
                }

                if let error = preferences.launchAtLoginError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Menu Bar") {
                Toggle("Show temperature", isOn: $preferences.showTemperatureInMenuBar)
                    .disabled(!hasTemperatureSensor)
                Text(hasTemperatureSensor
                     ? "Average CPU core temperature (same reading as Stats' \"Average CPU\"), updated every 2 seconds. Turns orange within 10°C of the trip threshold and red at it."
                     : "No temperature sensor available on this build.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Toggle("Show culprit CPU % when tripped", isOn: $preferences.showCPUInMenuBar)
                Text("When the breaker trips, the top swarm's CPU usage is added after the temperature.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { preferences.refreshLaunchAtLoginStatus() }
    }
}

// MARK: - Monitoring

private struct MonitoringSettingsTab: View {
    @Bindable var watchdog: WatchdogService

    var body: some View {
        Form {
            Section {
                Toggle("Notify when the breaker trips", isOn: $watchdog.autoAlertEnabled)
            } footer: {
                Text("Alerts are rate-limited to one per swarm every 60 seconds.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Temperature trip threshold")
                        Spacer()
                        Text(String(format: "%.0f°C", watchdog.temperatureThresholdCelsius))
                            .font(.system(.body, design: .monospaced, weight: .semibold))
                    }
                    Slider(value: $watchdog.temperatureThresholdCelsius, in: WatchdogService.thresholdRange, step: 1) {
                        EmptyView()
                    } minimumValueLabel: {
                        Text("\(Int(WatchdogService.thresholdRange.lowerBound))°").font(.caption2)
                    } maximumValueLabel: {
                        Text("\(Int(WatchdogService.thresholdRange.upperBound))°").font(.caption2)
                    }
                }

                if watchdog.temperatureThresholdCelsius != WatchdogService.defaultThresholdCelsius {
                    Button("Reset to \(Int(WatchdogService.defaultThresholdCelsius))°C") {
                        watchdog.temperatureThresholdCelsius = WatchdogService.defaultThresholdCelsius
                    }
                    .controlSize(.small)
                }
            } footer: {
                Text(sensorFootnote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Protected processes") {
                Text(ProcessController.protectedNames.sorted().joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
    }

    private var sensorFootnote: String {
        if let temp = watchdog.currentThermal.temperatureCelsius {
            return String(format: "Current average CPU core temperature %.1f°C. Sampling speeds up 5°C below the threshold.", temp)
        }
        return "No temperature sensor available. The breaker trips on macOS thermal state and CPU load only."
    }
}

// MARK: - About

private struct AboutTab: View {
    private static let repoURL = URL(string: "https://github.com/jcyrus/firebreak")!
    private static let issuesURL = URL(string: "https://github.com/jcyrus/firebreak/issues")!

    var body: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)

            VStack(spacing: 4) {
                Text("Firebreak")
                    .font(.title.weight(.semibold))
                Text(versionString)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Text("Thermal circuit breaker and runaway process-swarm watchdog for macOS.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)

            HStack(spacing: 16) {
                Link("GitHub", destination: Self.repoURL)
                Link("Report an Issue", destination: Self.issuesURL)
            }
            .font(.callout)

            Spacer()

            Text("© 2026 Cyrus Espiritu · MIT License")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        guard let version = info?["CFBundleShortVersionString"] as? String else {
            return "Development build"
        }
        let build = info?["CFBundleVersion"] as? String
        return build.map { "Version \(version) (\($0))" } ?? "Version \(version)"
    }
}
