import Foundation
import Observation

/// User settings, persisted in the app's own `UserDefaults` domain.
///
/// Everything here stays on this Mac. There is no sync, no account and no server.
@MainActor
@Observable
final class Preferences {
    private enum Key {
        static let enabled = "enabled"
        static let presetID = "presetID"
        static let closingIntensity = "closingIntensity"
        static let openingIntensity = "openingIntensity"
        static let smoothing = "smoothing"
        static let animatesClosing = "animatesClosing"
        static let animatesOpening = "animatesOpening"
        static let calibration = "hingeCalibration"
        static let tuning = "presetTuning"
        static let startAngle = "animationStartAngle"
        static let hasCompletedFirstRun = "hasCompletedFirstRun"
        static let debugLogging = "debugLogging"
        static let keepsAwake = "keepsAwakeWithLidShut"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.enabled: true,
            Key.presetID: AnimationPresetCatalog.defaultID,
            Key.closingIntensity: 1.0,
            Key.openingIntensity: 1.0,
            Key.smoothing: 0.25,
            Key.startAngle: HingeCalibration.defaultStartAngle,
            Key.animatesClosing: true,
            Key.animatesOpening: true,
            Key.hasCompletedFirstRun: false,
            Key.debugLogging: false,
            Key.keepsAwake: false,
        ])
        _enabled = defaults.bool(forKey: Key.enabled)
        _presetID = defaults.string(forKey: Key.presetID) ?? AnimationPresetCatalog.defaultID
        _closingIntensity = defaults.double(forKey: Key.closingIntensity)
        _openingIntensity = defaults.double(forKey: Key.openingIntensity)
        _smoothing = defaults.double(forKey: Key.smoothing)
        _startAngle = defaults.double(forKey: Key.startAngle)
        _animatesClosing = defaults.bool(forKey: Key.animatesClosing)
        _animatesOpening = defaults.bool(forKey: Key.animatesOpening)
        _hasCompletedFirstRun = defaults.bool(forKey: Key.hasCompletedFirstRun)
        _debugLogging = defaults.bool(forKey: Key.debugLogging)
        _keepsAwakeWithLidShut = defaults.bool(forKey: Key.keepsAwake)
        _calibration = Self.loadCalibration(from: defaults) ?? .default
        _tuning = Self.loadTuning(from: defaults)
    }

    var enabled: Bool {
        didSet { defaults.set(enabled, forKey: Key.enabled) }
    }

    var presetID: String {
        didSet { defaults.set(presetID, forKey: Key.presetID) }
    }

    var closingIntensity: Double {
        didSet { defaults.set(closingIntensity, forKey: Key.closingIntensity) }
    }

    var openingIntensity: Double {
        didSet { defaults.set(openingIntensity, forKey: Key.openingIntensity) }
    }

    var smoothing: Double {
        didSet { defaults.set(smoothing, forKey: Key.smoothing) }
    }

    /// Degrees above closed at which the animation starts.
    var startAngle: Double {
        didSet { defaults.set(startAngle, forKey: Key.startAngle) }
    }

    var animatesClosing: Bool {
        didSet { defaults.set(animatesClosing, forKey: Key.animatesClosing) }
    }

    var animatesOpening: Bool {
        didSet { defaults.set(animatesOpening, forKey: Key.animatesOpening) }
    }

    var hasCompletedFirstRun: Bool {
        didSet { defaults.set(hasCompletedFirstRun, forKey: Key.hasCompletedFirstRun) }
    }

    var debugLogging: Bool {
        didSet { defaults.set(debugLogging, forKey: Key.debugLogging) }
    }

    /// Whether Bendable asked for the Mac to stay up with the lid shut.
    ///
    /// This records the request, not the system state. The setting itself is global and
    /// outlives the app, so the two are compared on every launch rather than one being
    /// trusted to imply the other.
    var keepsAwakeWithLidShut: Bool {
        didSet { defaults.set(keepsAwakeWithLidShut, forKey: Key.keepsAwake) }
    }

    var calibration: HingeCalibration {
        didSet {
            guard let data = try? JSONEncoder().encode(calibration) else { return }
            defaults.set(data, forKey: Key.calibration)
        }
    }

    /// Tuning is kept per preset, so switching styles and switching back does not
    /// lose whatever the last one was set to.
    private var tuning: [String: PresetTuning] {
        didSet {
            guard let data = try? JSONEncoder().encode(tuning) else { return }
            defaults.set(data, forKey: Key.tuning)
        }
    }

    func tuning(for presetID: String) -> PresetTuning {
        tuning[presetID] ?? .default
    }

    func setTuning(_ value: PresetTuning, for presetID: String) {
        tuning[presetID] = value
    }

    var currentTuning: PresetTuning {
        get { tuning(for: presetID) }
        set { setTuning(newValue, for: presetID) }
    }

    func resetTuning(for presetID: String) {
        tuning.removeValue(forKey: presetID)
    }

    func resetCalibration() {
        calibration = .default
        defaults.removeObject(forKey: Key.calibration)
    }

    private static func loadCalibration(from defaults: UserDefaults) -> HingeCalibration? {
        guard let data = defaults.data(forKey: Key.calibration) else { return nil }
        return try? JSONDecoder().decode(HingeCalibration.self, from: data)
    }

    private static func loadTuning(from defaults: UserDefaults) -> [String: PresetTuning] {
        guard let data = defaults.data(forKey: Key.tuning),
              let decoded = try? JSONDecoder().decode([String: PresetTuning].self, from: data)
        else { return [:] }
        return decoded
    }
}
