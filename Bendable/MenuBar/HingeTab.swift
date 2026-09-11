import SwiftUI

/// How the animation answers the hinge, as opposed to what it looks like.
struct HingeTab: View {
    @Environment(AppCoordinator.self) private var coordinator

    var body: some View {
        @Bindable var preferences = coordinator.preferences

        VStack(alignment: .leading, spacing: 10) {
            SettingsGroup("Runs when") {
                SwitchRow(
                    title: "Closing the lid",
                    help: "Animate as the lid comes down.",
                    isOn: $preferences.animatesClosing
                )
                SwitchRow(
                    title: "Opening the lid",
                    help: "Animate as the lid comes back up.",
                    isOn: $preferences.animatesOpening
                )
            }

            SettingsGroup("Feel") {
                QuietButton("Reset") {
                    preferences.startAngle = HingeCalibration.defaultStartAngle
                    preferences.closingIntensity = 1
                    preferences.openingIntensity = 1
                    preferences.smoothing = 0.25
                }
                .help("Put these four back to where they shipped.")
            } content: {
                DegreeSlider(
                    title: "Starts at",
                    value: $preferences.startAngle,
                    range: 20...100,
                    defaultValue: HingeCalibration.defaultStartAngle,
                    help: "How far above shut the effect begins in earnest."
                )
                PercentSlider(
                    title: "Closing", value: $preferences.closingIntensity,
                    help: "Strength of the whole effect on the way down."
                )
                PercentSlider(
                    title: "Opening", value: $preferences.openingIntensity,
                    help: "Strength of the whole effect on the way up."
                )
                PercentSlider(
                    title: "Smoothing", value: $preferences.smoothing, defaultValue: 0.25,
                    help: "More is steadier and slightly slower to answer. Less follows the hinge harder."
                )
            }

            HingeTravelMap(
                closedAngle: coordinator.state.calibration.closedAngle,
                openAngle: coordinator.state.calibration.openAngle,
                bandUpperBound: coordinator.state.animationRange.upperBound,
                currentAngle: coordinator.state.hinge.angle
            )
            .padding(.top, 2)

            Note(startAngleNote)

            LidShutSection()
        }
    }

    private var startAngleNote: String {
        let range = coordinator.state.animationRange
        let band = range.upperBound - range.lowerBound
        let requested = coordinator.preferences.startAngle
        if band < requested - 1 {
            return String(
                format: "Most of the effect waits until the lid is below %.0f°. Your lid rests too low for %.0f°, so it is using %.0f° of travel.",
                range.upperBound, requested, band
            )
        }
        return String(
            format: "Most of the effect waits until the lid is below %.0f°. Above that it still answers, gently.",
            range.upperBound
        )
    }
}
