import SwiftUI

/// Picks the animation by showing what each one does, rather than by naming it.
struct StyleTab: View {
    @Environment(AppCoordinator.self) private var coordinator

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 7), count: 3)

    var body: some View {
        @Bindable var preferences = coordinator.preferences

        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: columns, spacing: 7) {
                ForEach(AnimationPresetCatalog.all, id: \.id) { preset in
                    StyleCard(
                        preset: preset,
                        tuning: preferences.tuning(for: preset.id),
                        isSelected: preset.id == preferences.presetID
                    )
                    .onTapGesture { preferences.presetID = preset.id }
                }
            }

            if coordinator.state.isSubstitutingPreset {
                ScreenCapturePrompt(
                    presetName: AnimationPresetCatalog.preset(id: preferences.presetID).name
                )
            }

            AppearanceControls()
        }
    }
}

private struct StyleCard: View {
    let preset: any AnimationPreset
    let tuning: PresetTuning
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 0) {
            PresetThumbnail(preset: preset, tuning: tuning, height: 50)

            HStack(spacing: 4) {
                Text(preset.name)
                    .font(.system(size: 10.5, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.tint)
                }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 5)
        }
        .background(
            isSelected ? AnyShapeStyle(.tint.opacity(0.13)) : AnyShapeStyle(.quaternary.opacity(0.3)),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), lineWidth: 1.5)
        }
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(preset.name)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// Shown when the chosen style is not the one being rendered.
///
/// The engine falls back to a plain fade when it cannot have the desktop image, which
/// is right, but is indistinguishable from the chosen style being broken unless the
/// interface says what is happening.
private struct ScreenCapturePrompt: View {
    @Environment(AppCoordinator.self) private var coordinator
    let presetName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label {
                Text("\(presetName) is showing as a plain fade")
                    .font(.system(size: 11.5, weight: .medium))
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            }

            Text("It redraws your desktop as the lid moves, which needs Screen Recording permission. macOS usually needs Bendable restarted once you have allowed it.")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                Button("Allow…") { coordinator.requestScreenCapturePermission() }
                Button("Restart") { coordinator.relaunch() }
            }
            .font(.system(size: 11))
            .controlSize(.small)
        }
        .padding(9)
        .background(
            .orange.opacity(0.10),
            in: RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous)
        )
    }
}
