import SwiftUI

/// Where the effect lives, drawn against the travel of the lid you actually have.
///
/// "Starts at 45°" means nothing on its own: it depends on where your lid rests, and
/// the number quietly gets capped when it cannot have what it asked for. Showing the
/// band against the full sweep, with the live angle riding on it, makes the setting and
/// the cap both obvious without a paragraph explaining either.
struct HingeTravelMap: View {
    let closedAngle: Double
    let openAngle: Double
    /// Top of the band. Already capped by the calibration, not the requested value.
    let bandUpperBound: Double
    let currentAngle: Double?

    private var travel: Double { max(openAngle - closedAngle, 1) }

    private func fraction(_ angle: Double) -> Double {
        clamp((angle - closedAngle) / travel, 0, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geometry in
                let width = geometry.size.width
                let bandWidth = width * fraction(bandUpperBound)

                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary.opacity(0.5))

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.accentColor.opacity(0.85), .accentColor.opacity(0.18)],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .frame(width: bandWidth)

                    if let currentAngle {
                        Capsule()
                            .fill(.white)
                            .frame(width: 2.5)
                            .offset(x: (width - 2.5) * fraction(currentAngle))
                            .shadow(color: .black.opacity(0.5), radius: 1.5)
                    }
                }
            }
            .frame(height: 10)

            HStack(spacing: 0) {
                Text("Shut")
                Spacer(minLength: 6)
                if let currentAngle {
                    Text(String(format: "now %.0f°", currentAngle))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 6)
                }
                Text(String(format: "rests at %.0f°", openAngle))
            }
            .font(.system(size: 9.5))
            .foregroundStyle(.tertiary)
        }
        .help("The shaded part is where most of the effect happens.")
    }
}
