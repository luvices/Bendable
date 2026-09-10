import Foundation

protocol AnimationPreset: Sendable {
    static var id: String { get }
    var id: String { get }
    var name: String { get }
    var summary: String { get }
    /// True when the preset needs the desktop image to look right.
    var requiresScreenCapture: Bool { get }
    /// Which tuning sliders this preset responds to.
    var supportedControls: PresetControl { get }

    /// Pure mapping from hinge state to a frame. Must not touch UIKit/AppKit or the GPU.
    ///
    /// - Parameter progress: 1 = lid fully open, 0 = closed.
    /// - Parameter velocity: progress units per second; negative while closing.
    func frame(
        progress: Double,
        velocity: Double,
        direction: HingeDirection,
        context: AnimationContext
    ) -> FrameDescription
}

extension AnimationPreset {
    var id: String { Self.id }
    var requiresScreenCapture: Bool { false }
    var supportedControls: PresetControl { .dimming }
}

/// The shipping presets, in menu order.
enum AnimationPresetCatalog {
    static let all: [any AnimationPreset] = [
        FoldPreset(), CreasePreset(), FadePreset(), AperturePreset(), ShutterPreset(),
    ]

    static let defaultID = FoldPreset.id

    static func preset(id: String) -> any AnimationPreset {
        all.first { $0.id == id } ?? FoldPreset()
    }
}
