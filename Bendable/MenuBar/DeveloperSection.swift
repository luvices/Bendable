#if DEBUG
import SwiftUI

/// Debug-only. Drives the whole pipeline without touching the laptop.
struct DeveloperSection: View {
    @Environment(AppCoordinator.self) private var coordinator
    @State private var useSimulator = false
    @State private var simulatedAngle: Double = 95
    @State private var isConnected = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsGroup("Simulated hinge") {
                SwitchRow(title: "Use simulator", isOn: Binding(
                    get: { useSimulator },
                    set: { newValue in
                        useSimulator = newValue
                        coordinator.useSimulatedHinge(newValue)
                        if newValue { emit() }
                    }
                ))
                DegreeSlider(title: "Angle", value: $simulatedAngle, range: 0...140)
                    .disabled(!useSimulator)
                    .onChange(of: simulatedAngle) { _, _ in emit() }
                SwitchRow(title: "Sensor connected", isOn: Binding(
                    get: { isConnected },
                    set: { newValue in
                        isConnected = newValue
                        coordinator.simulator?.isConnected = newValue
                    }
                ))
                .disabled(!useSimulator)
            }

            SettingsGroup("Inject") {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 84), spacing: 5)], spacing: 5
                ) {
                    ForEach(PowerEvent.allCases, id: \.rawValue) { event in
                        Button(label(for: event)) { coordinator.injectPowerEvent(event) }
                            .controlSize(.small)
                            .font(.system(size: 10.5))
                    }
                }
                .rowPadding()
            }

            SettingsGroup("Live") {
                Readout(
                    title: "Velocity",
                    value: String(format: "%+.3f /s", coordinator.state.hinge.velocity)
                )
                Readout(title: "Direction", value: coordinator.state.hinge.direction.rawValue)
                Readout(
                    title: "Frame time",
                    value: coordinator.state.frameInterval > 0
                        ? String(format: "%.2f ms", coordinator.state.frameInterval * 1000) : "idle"
                )
            }
        }
    }

    private func emit() {
        coordinator.simulator?.emit(angle: simulatedAngle)
    }

    private func label(for event: PowerEvent) -> String {
        switch event {
        case .systemWillSleep: "Sleep"
        case .systemDidWake: "Wake"
        case .displaysDidSleep: "Display off"
        case .displaysDidWake: "Display on"
        case .screenLocked: "Lock"
        case .screenUnlocked: "Unlock"
        }
    }
}
#endif
