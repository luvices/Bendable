import SwiftUI

/// The whole interface. Bendable has no settings window: everything it can do fits in
/// one popover, and a utility this small does not deserve a second place to look.
///
/// Laid out across rather than down. The preview sits permanently beside the controls,
/// so a slider and what it does to the picture are visible at the same time, and the
/// controls are tabbed so nothing has to scroll to be found.
struct MenuBarView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @State private var tab: PopoverTab
    @State private var closure: Double = 0.62

    init(tab: PopoverTab = .style) {
        _tab = State(initialValue: tab)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            HStack(spacing: 0) {
                PreviewPane(closure: $closure)
                    .padding(Metrics.gutter)
                    .frame(width: Metrics.previewPane, height: Metrics.bodyHeight)

                Divider()

                controls
                    .frame(width: Metrics.controlPane, height: Metrics.bodyHeight)
            }
            .opacity(coordinator.preferences.enabled ? 1 : 0.45)
            .allowsHitTesting(coordinator.preferences.enabled)

            Divider()
            footer
        }
        .frame(width: Metrics.width)
        .animation(.snappy(duration: 0.2), value: coordinator.preferences.enabled)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 0) {
            TabBar(selection: $tab)
                .padding(.horizontal, Metrics.gutter - 4)
                .padding(.top, 11)
                .padding(.bottom, 9)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    switch tab {
                    case .style: StyleTab()
                    case .hinge: HingeTab()
                    case .status: StatusTab()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Metrics.gutter)
                .padding(.bottom, Metrics.gutter)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var header: some View {
        @Bindable var preferences = coordinator.preferences

        return HStack(spacing: 10) {
            Image(systemName: "laptopcomputer")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 26, height: 26)
                .background(.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text("Bendable")
                    .font(.system(size: 13, weight: .semibold))
                Text(statusLine)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            .help(coordinator.state.capability.explanation)

            Spacer(minLength: 8)

            Toggle("", isOn: $preferences.enabled)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .help(preferences.enabled ? "Stop animating the lid." : "Start animating the lid.")
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.vertical, 10)
    }

    private var statusLine: String {
        guard coordinator.preferences.enabled else { return "Paused" }
        switch coordinator.state.capability {
        case .continuousAngle: return "Following the hinge"
        case .lidStateOnly: return "Open and shut only, no angle"
        case .unsupported: return "No lid sensor on this Mac"
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Toggle("Open at login", isOn: Binding(
                get: { coordinator.state.launchAtLoginEnabled },
                set: { coordinator.setLaunchAtLogin($0) }
            ))
            .toggleStyle(.checkbox)

            Spacer(minLength: 8)

            Button("Quit Bendable") { NSApplication.shared.terminate(nil) }
        }
        .font(.system(size: 11))
        .controlSize(.small)
        .padding(.horizontal, Metrics.gutter)
        .padding(.vertical, 9)
    }
}
