import SwiftUI

/// What the sensor is doing, and the two things worth resetting when it misbehaves.
/// Also the section to quote in a bug report.
struct StatusTab: View {
    @Environment(AppCoordinator.self) private var coordinator

    var body: some View {
        @Bindable var preferences = coordinator.preferences
        let state = coordinator.state

        VStack(alignment: .leading, spacing: 10) {
            SettingsGroup("Sensor") {
                QuietButton("Copy") { copyDiagnostics() }
                    .help("Copies these readings, ready to paste into a bug report.")
            } content: {
                Readout(title: "Lid tracking", value: state.capability.localizedDescription)
                Readout(
                    title: "Raw reading",
                    value: state.rawAngle.map { String(format: "%.1f°", $0) } ?? "none"
                )
                Readout(
                    title: "Filtered",
                    value: state.hinge.angle.map { String(format: "%.1f°", $0) } ?? "none"
                )
                Readout(title: "Update rate", value: String(format: "%.0f Hz", state.sensorRate))
                Readout(title: "Phase", value: state.phase.rawValue)
                Readout(
                    title: "Drawing",
                    value: state.framesPerSecond > 0
                        ? String(format: "%.0f fps", state.framesPerSecond) : "idle"
                )
            }

            SettingsGroup("Your hinge") {
                QuietButton("Relearn") { coordinator.resetCalibration() }
            } content: {
                Readout(
                    title: "Rests at",
                    value: String(format: "%.1f°", state.calibration.openAngle)
                )
                Readout(
                    title: "Effect starts at",
                    value: String(format: "%.1f°", state.animationRange.upperBound)
                )
            }

            Note("Bendable learns the range of your hinge as you use it. Relearn if the effect stops lining up with the lid.")

            SettingsGroup("Permissions") {
                if !state.screenCaptureGranted {
                    QuietButton("Allow…") { coordinator.requestScreenCapturePermission() }
                }
            } content: {
                Readout(
                    title: "Screen recording",
                    value: state.screenCaptureGranted ? "Allowed" : "Not allowed"
                )
                SwitchRow(
                    title: "Debug logging",
                    help: "Writes detail to the unified log. Never records what is on screen.",
                    isOn: $preferences.debugLogging
                )
            }

            #if DEBUG
            DeveloperSection()
            #endif
        }
    }

    private static let version: String = {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }()

    private func copyDiagnostics() {
        let state = coordinator.state
        let lines = [
            "Bendable \(Self.version)",
            "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "Lid tracking: \(state.capability.localizedDescription)",
            "Raw: \(state.rawAngle.map { String(format: "%.1f", $0) } ?? "none")",
            "Filtered: \(state.hinge.angle.map { String(format: "%.1f", $0) } ?? "none")",
            String(format: "Update rate: %.0f Hz", state.sensorRate),
            "Phase: \(state.phase.rawValue)",
            String(format: "Calibration: %.1f to %.1f", state.calibration.closedAngle, state.calibration.openAngle),
            String(format: "Band: %.1f", state.animationRange.upperBound),
            "Style: \(coordinator.preferences.presetID)",
            "Screen recording: \(state.screenCaptureGranted ? "allowed" : "not allowed")",
        ]
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }
}
