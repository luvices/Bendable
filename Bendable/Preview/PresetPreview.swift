import AppKit
import SwiftUI

/// Renders the selected preset at an explicit progress value.
///
/// This goes through `AnimationEngine` and `PresetRenderer`, the same objects the
/// overlay uses, so the scrubber is a genuine test of the shipping path rather than a
/// lookalike.
struct PresetPreview: NSViewRepresentable {
    @Environment(AppCoordinator.self) private var coordinator
    let progress: Double

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let container = PreviewContainerView()
        let renderer = PresetRenderer()
        let view = MetalPresetView(renderer: renderer)
        container.addSubview(view)
        container.metalView = view
        context.coordinator.view = view
        context.coordinator.renderer = renderer
        context.coordinator.loadSampleImage(into: view)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let engine = context.coordinator.engine(for: coordinator)
        engine.context.captureAvailable = true
        let direction: HingeDirection = progress < context.coordinator.lastProgress ? .closing : .opening
        context.coordinator.lastProgress = progress
        context.coordinator.view?.renderImmediately(
            engine.frame(progress: progress, direction: direction)
        )
    }

    @MainActor
    final class Coordinator {
        var view: MetalPresetView?
        var renderer: PresetRenderer?
        var lastProgress: Double = 1
        private var cachedEngine: AnimationEngine?
        private var cachedPresetID: String?

        func engine(for appCoordinator: AppCoordinator) -> AnimationEngine {
            let preferences = appCoordinator.preferences
            let engine: AnimationEngine
            if let cachedEngine, cachedPresetID == preferences.presetID {
                engine = cachedEngine
            } else {
                engine = appCoordinator.makePreviewEngine()
                cachedEngine = engine
                cachedPresetID = preferences.presetID
            }
            // Re-read every frame: the scrubber has to reflect slider drags live.
            engine.context.closingIntensity = preferences.closingIntensity
            engine.context.openingIntensity = preferences.openingIntensity
            engine.context.tuning = preferences.currentTuning
            return engine
        }

        /// Uses the real desktop when permission already exists, and a locally drawn
        /// stand-in otherwise, so opening Settings never triggers a permission prompt.
        func loadSampleImage(into view: MetalPresetView) {
            view.setCapturedImage(PreviewImage.placeholder())
            guard ScreenCapture.permissionState == .granted else { return }
            let capture = ScreenCapture()
            Task { @MainActor in
                if let image = await capture.captureBuiltInDisplay() {
                    view.setCapturedImage(image)
                }
            }
        }
    }
}

/// Keeps the Metal view filling the SwiftUI-provided bounds.
private final class PreviewContainerView: NSView {
    var metalView: NSView?

    override func layout() {
        super.layout()
        metalView?.frame = bounds
    }

    override var isFlipped: Bool { true }
}
