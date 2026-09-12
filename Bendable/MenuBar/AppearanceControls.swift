import SwiftUI

/// The sliders for whatever the selected style responds to.
///
/// They sit directly under the style grid rather than in a tab of their own, so the
/// thumbnail being changed and the control changing it are a few pixels apart.
struct AppearanceControls: View {
    @Environment(AppCoordinator.self) private var coordinator

    var body: some View {
        @Bindable var preferences = coordinator.preferences
        let preset = AnimationPresetCatalog.preset(id: preferences.presetID)
        let controls = PresetControl.displayOrder.filter { preset.supportedControls.contains($0) }

        if controls.isEmpty {
            Note("\(preset.name) has nothing to adjust. Set how it answers the lid under Hinge.")
        } else {
            SettingsGroup("Adjust \(preset.name)") {
                QuietButton("Reset") { preferences.resetTuning(for: preferences.presetID) }
                    .help("Put every slider here back to where it shipped. Double-click one name to reset just that one.")
            } content: {
                ForEach(controls, id: \.rawValue) { control in
                    PercentSlider(
                        title: control.title,
                        value: Binding(
                            get: { preferences.currentTuning[control] },
                            set: { newValue in
                                var tuning = preferences.currentTuning
                                tuning[control] = newValue
                                preferences.currentTuning = tuning
                            }
                        ),
                        defaultValue: PresetTuning.default[control],
                        help: control.explanation
                    )
                }
            }
        }
    }
}

extension PresetControl {
    /// Shown on hover. Says what the control does to the picture, not what it scales
    /// in the code.
    var explanation: String {
        switch self {
        case .perspective: "How much the screen appears to recede as it tips back."
        case .tilt: "How far the screen turns away for a given lid angle."
        case .blur: "How far out of focus the screen drifts as it closes."
        case .variableBlur: "Keeps the hinge edge sharper than the far edge. At zero, blur and washout apply evenly."
        case .washout: "How much colour drains out of the screen as it turns away."
        case .corners: "How rounded the corners of the screen are."
        case .dimming: "How far the screen fades toward black."
        case .strength: "Overall strength of the spatial anchoring and close effect."
        case .sunSize: "Diameter of the sun at the horizon."
        case .glow: "Reach and intensity of the sun bloom and atmospheric glow."
        case .exposure: "Brightness and highlight rolloff of the procedural sky."
        case .warmth: "How strongly the daylight moves through gold, orange and red."
        case .horizon: "Vertical position of the horizon and the sun's crossing point."
        case .darkness: "How early twilight falls toward near-black."
        default: ""
        }
    }
}
