import Foundation

/// Which controls a preset actually responds to.
///
/// The popover shows only the sliders the selected preset uses, so a preset that
/// does not deform anything never offers a Perspective control.
struct PresetControl: OptionSet, Sendable, Hashable {
    let rawValue: Int

    static let perspective = PresetControl(rawValue: 1 << 0)
    static let tilt = PresetControl(rawValue: 1 << 1)
    static let blur = PresetControl(rawValue: 1 << 2)
    static let variableBlur = PresetControl(rawValue: 1 << 3)
    static let washout = PresetControl(rawValue: 1 << 4)
    static let corners = PresetControl(rawValue: 1 << 5)
    static let dimming = PresetControl(rawValue: 1 << 6)

    static let none: PresetControl = []
}

/// Per-preset strengths, each 0...1 and each scaling one of the ramps a preset
/// produces. Stored per preset so switching styles does not lose the last one's feel.
struct PresetTuning: Sendable, Hashable, Codable {
    var perspective: Double = 1
    var tilt: Double = 1
    var blur: Double = 1
    /// How much the blur and washout are graded along the panel. 0 applies them
    /// evenly, 1 leaves the hinge edge untouched.
    var variableBlur: Double = 0.85
    var washout: Double = 1
    var corners: Double = 1
    var dimming: Double = 1

    static let `default` = PresetTuning()

    subscript(control: PresetControl) -> Double {
        get {
            switch control {
            case .perspective: perspective
            case .tilt: tilt
            case .blur: blur
            case .variableBlur: variableBlur
            case .washout: washout
            case .corners: corners
            case .dimming: dimming
            default: 0
            }
        }
        set {
            let value = clamp(newValue, 0, 1)
            switch control {
            case .perspective: perspective = value
            case .tilt: tilt = value
            case .blur: blur = value
            case .variableBlur: variableBlur = value
            case .washout: washout = value
            case .corners: corners = value
            case .dimming: dimming = value
            default: break
            }
        }
    }
}

extension PresetControl {
    /// Order the sliders appear in.
    static let displayOrder: [PresetControl] = [
        .perspective, .tilt, .blur, .variableBlur, .washout, .corners, .dimming,
    ]

    var title: String {
        switch self {
        case .perspective: "Perspective"
        case .tilt: "Tilt"
        case .blur: "Blur"
        case .variableBlur: "Variable blur"
        case .washout: "Washout"
        case .corners: "Corner rounding"
        case .dimming: "Dimming"
        default: ""
        }
    }
}
