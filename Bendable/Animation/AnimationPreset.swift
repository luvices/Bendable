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

    /// Where along the travel the picker samples this preset for its thumbnail.
    ///
    /// One number cannot serve every preset. The turning ones read clearly early,
    /// while the ones that start slowly and leave late are still almost untouched
    /// there, so a shared sample point renders half the grid as identical pictures of
    /// an unmodified desktop.
    var thumbnailProgress: Double { get }

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
    var thumbnailProgress: Double { 0.68 }
}

/// The shipping presets, in menu order.
enum AnimationPresetCatalog {
    static let all: [any AnimationPreset] = [
        FoldPreset(), MacDuoPreset(), SunsetHDRPreset(),
        CreasePreset(), CurlPreset(), RecedePreset(), SlidePreset(),
        FadePreset(), AperturePreset(), ShutterPreset(), BlindsPreset(),
    ]

    static let defaultID = FoldPreset.id

    static func preset(id: String) -> any AnimationPreset {
        all.first { $0.id == id } ?? FoldPreset()
    }
}
