import SwiftUI

/// The left half of the popover: what the effect looks like, at whatever angle you
/// point it at.
///
/// It sits beside the controls rather than under them so a slider and its result are
/// visible at once. The render goes through `AnimationEngine` and `PresetRenderer`, the
/// same objects the overlay uses, so this is the shipping path rather than a lookalike.
struct PreviewPane: View {
    @Environment(AppCoordinator.self) private var coordinator
    /// 0 is a lid wide open, 1 is shut. The slider reads left to right as closing,
    /// which is the direction the effect is about.
    @Binding var closure: Double

    var body: some View {
        let preset = AnimationPresetCatalog.preset(id: coordinator.preferences.presetID)

        VStack(alignment: .leading, spacing: 0) {
            preview(of: preset)
                .frame(height: 214)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(.primary.opacity(0.10))
                }
                .shadow(color: .black.opacity(0.28), radius: 9, y: 3)

            scrubber
                .padding(.top, 12)

            VStack(alignment: .leading, spacing: 3) {
                Text(preset.name)
                    .font(.system(size: 13, weight: .semibold))
                Text(preset.summary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 14)

            Spacer(minLength: 10)

            Button {
                coordinator.runPreview()
            } label: {
                Label("Play on screen", systemImage: "play.fill")
                    .font(.system(size: 11.5))
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.small)
            .disabled(!coordinator.preferences.enabled)
            .help("Runs the effect full screen, exactly as closing the lid would.")
        }
    }

    @ViewBuilder
    private func preview(of preset: any AnimationPreset) -> some View {
        #if DEBUG
        if PopoverSnapshot.isRendering,
           let still = PresetThumbnailRenderer.shared.image(
               for: preset,
               tuning: coordinator.preferences.tuning(for: preset.id),
               progress: 1 - closure
           ) {
            Image(decorative: still, scale: 2)
                .resizable()
                .scaledToFill()
                .frame(width: Metrics.previewPane - Metrics.gutter * 2, height: 214)
                .clipped()
        } else {
            PresetPreview(progress: 1 - closure)
        }
        #else
        PresetPreview(progress: 1 - closure)
        #endif
    }

    private var scrubber: some View {
        VStack(spacing: 3) {
            Slider(value: $closure, in: 0...1)
                .controlSize(.mini)
            HStack {
                Text("Open")
                Spacer()
                Text("Shut")
            }
            .font(.system(size: 9.5))
            .foregroundStyle(.tertiary)
        }
        .help("Drag to move the hinge by hand.")
    }
}
