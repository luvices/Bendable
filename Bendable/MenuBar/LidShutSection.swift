import SwiftUI

/// The one switch in Bendable that changes something outside Bendable.
///
/// It is deliberately loud about it. Everything else here is a preference; this alters
/// a system setting that survives quitting the app, needs a password both ways, and
/// leaves a laptop running inside a closed bag. The interface says so plainly rather
/// than reading like another checkbox.
struct LidShutSection: View {
    @Environment(AppCoordinator.self) private var coordinator

    var body: some View {
        let status = coordinator.state.sleepGuard

        SettingsGroup("With the lid shut") {
            SwitchRow(
                title: "Keep the Mac awake",
                help: "Turns off lid-close sleep, so work carries on with the lid down. Needs your password.",
                isOn: Binding(
                    get: { status.isActive },
                    set: { coordinator.setKeepAwakeWithLidShut($0) }
                )
            )
        }

        switch status {
        case .off:
            Note("Downloads, builds and renders carry on with the lid down. macOS asks for your password, because this changes a system setting rather than a Bendable one.")
        case .on:
            Caution("Your Mac will not sleep when you shut the lid. It keeps drawing power and making heat, so unplug it from a bag rather than a desk. This stays on after Bendable quits.")
        case .onFromElsewhere:
            Caution("Lid-close sleep is already off, but Bendable did not turn it off. Another app, a Terminal command, or a previous run of Bendable that was killed. Switching this off will clear it.")
        case .revokedElsewhere:
            EmptyView()
        }

        if let problem = coordinator.state.sleepGuardProblem {
            Caution(problem)
        }
    }
}

/// A note with a warning triangle, for the things that outlast the app.
struct Caution: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 9.5))
                .foregroundStyle(.orange)
                .padding(.top, 1.5)
            Text(text)
                .font(.note)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 2)
    }
}
