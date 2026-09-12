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
    static let strength = PresetControl(rawValue: 1 << 7)
    static let sunSize = PresetControl(rawValue: 1 << 8)
    static let glow = PresetControl(rawValue: 1 << 9)
    static let exposure = PresetControl(rawValue: 1 << 10)
    static let warmth = PresetControl(rawValue: 1 << 11)
    static let horizon = PresetControl(rawValue: 1 << 12)
    static let darkness = PresetControl(rawValue: 1 << 13)

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
    var strength: Double = 0.88
    var sunSize: Double = 0.55
    var glow: Double = 0.72
    var exposure: Double = 0.65
    var warmth: Double = 0.7
    var horizon: Double = 0.56
    var darkness: Double = 0.9

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
            case .strength: strength
            case .sunSize: sunSize
            case .glow: glow
            case .exposure: exposure
            case .warmth: warmth
            case .horizon: horizon
            case .darkness: darkness
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
            case .strength: strength = value
            case .sunSize: sunSize = value
            case .glow: glow = value
            case .exposure: exposure = value
            case .warmth: warmth = value
            case .horizon: horizon = value
            case .darkness: darkness = value
            default: break
            }
        }
    }
}

extension PresetControl {
    /// Order the sliders appear in.
    static let displayOrder: [PresetControl] = [
        .perspective, .tilt, .blur, .variableBlur, .washout, .corners, .dimming, .strength,
        .sunSize, .glow, .exposure, .warmth, .horizon, .darkness,
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
        case .strength: "Strength"
        case .sunSize: "Sun Size"
        case .glow: "Glow"
        case .exposure: "Exposure"
        case .warmth: "Warmth"
        case .horizon: "Horizon"
        case .darkness: "Darkness"
        default: ""
        }
    }
}

// Decode fields individually so settings written by older Bendable builds keep
// working when new controls are added.
extension PresetTuning {
    private enum CodingKeys: String, CodingKey {
        case perspective, tilt, blur, variableBlur, washout, corners, dimming
        case strength, sunSize, glow, exposure, warmth, horizon, darkness
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self.default
        perspective = try values.decodeIfPresent(Double.self, forKey: .perspective) ?? defaults.perspective
        tilt = try values.decodeIfPresent(Double.self, forKey: .tilt) ?? defaults.tilt
        blur = try values.decodeIfPresent(Double.self, forKey: .blur) ?? defaults.blur
        variableBlur = try values.decodeIfPresent(Double.self, forKey: .variableBlur) ?? defaults.variableBlur
        washout = try values.decodeIfPresent(Double.self, forKey: .washout) ?? defaults.washout
        corners = try values.decodeIfPresent(Double.self, forKey: .corners) ?? defaults.corners
        dimming = try values.decodeIfPresent(Double.self, forKey: .dimming) ?? defaults.dimming
        strength = try values.decodeIfPresent(Double.self, forKey: .strength) ?? defaults.strength
        sunSize = try values.decodeIfPresent(Double.self, forKey: .sunSize) ?? defaults.sunSize
        glow = try values.decodeIfPresent(Double.self, forKey: .glow) ?? defaults.glow
        exposure = try values.decodeIfPresent(Double.self, forKey: .exposure) ?? defaults.exposure
        warmth = try values.decodeIfPresent(Double.self, forKey: .warmth) ?? defaults.warmth
        horizon = try values.decodeIfPresent(Double.self, forKey: .horizon) ?? defaults.horizon
        darkness = try values.decodeIfPresent(Double.self, forKey: .darkness) ?? defaults.darkness
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(perspective, forKey: .perspective)
        try values.encode(tilt, forKey: .tilt)
        try values.encode(blur, forKey: .blur)
        try values.encode(variableBlur, forKey: .variableBlur)
        try values.encode(washout, forKey: .washout)
        try values.encode(corners, forKey: .corners)
        try values.encode(dimming, forKey: .dimming)
        try values.encode(strength, forKey: .strength)
        try values.encode(sunSize, forKey: .sunSize)
        try values.encode(glow, forKey: .glow)
        try values.encode(exposure, forKey: .exposure)
        try values.encode(warmth, forKey: .warmth)
        try values.encode(horizon, forKey: .horizon)
        try values.encode(darkness, forKey: .darkness)
    }
}
