import SwiftUI

/// One screen, one decision. Permissions are explained later, and only if a preset
/// actually needs them.
struct WelcomeView: View {
    @Environment(AppCoordinator.self) private var coordinator
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "laptopcomputer")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)

            Text("Make opening your Mac feel better.")
                .font(.title2)
                .multilineTextAlignment(.center)

            Text(coordinator.state.capability.explanation)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            Button("Enable") {
                coordinator.preferences.enabled = true
                coordinator.preferences.hasCompletedFirstRun = true
                onDone()
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.large)
        }
        .padding(.horizontal, 36)
        .padding(.bottom, 32)
        .padding(.top, 12)
        .frame(width: 400)
    }
}
