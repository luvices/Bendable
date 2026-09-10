import AppKit
import Foundation

/// Owns the overlay window and turns state-machine transitions into rendering.
@MainActor
final class OverlayCoordinator {
    /// Openness at which the desktop still is fetched.
    ///
    /// A screenshot takes tens of milliseconds, so waiting for the engage threshold
    /// would mean the overlay arrives after the lid has visibly moved. This fires on
    /// the first sensor reading that is not exactly at rest, well before anything is
    /// drawn.
    private static let capturePrimeThreshold = 0.9995

    /// Progress units per second below which the lid counts as genuinely moving.
    ///
    /// Instantaneous velocity is used rather than the reported direction because the
    /// direction decision is deliberately averaged over ~90 ms, and the whole point of
    /// priming here is to be early.
    private static let movementVelocity = -0.01

    /// How old a held desktop still may be before it is refreshed.
    ///
    /// Refreshing happens in the background while the previous image keeps rendering,
    /// so a stale frame costs nothing but a briefly out-of-date desktop.
    private static let captureMaxAge: TimeInterval = 2

    private let engine: AnimationEngine
    private let capture = ScreenCapture()
    private let renderer: PresetRenderer?
    private var view: MetalPresetView?
    private var window: OverlayWindow?

    /// The most recent reading. The display link interpolates toward this rather than
    /// the render being driven by the readings themselves.
    private var latestState: HingeState = .open
    private var animator = ProgressAnimator()

    private var captureTask: Task<Void, Never>?
    private var hasTexture = false
    private var textureTimestamp: TimeInterval = 0
    private var isTracking = false
    private var wantsWindowVisible = false
    private var screenObserver: NotificationObserverToken?

    var onFrameTiming: ((Double) -> Void)?
    /// Diagnostics: every display link callback, and every frame handed to the GPU.
    var onDisplayLinkTick: (() -> Void)?
    var onFrameRendered: ((FrameDescription) -> Void)?
    /// The tracked value itself, which is what smoothness is a property of. Frame
    /// descriptions differ per preset, and a preset that deforms nothing would report a
    /// perfectly smooth animation of nothing.
    var onProgressRendered: ((Double) -> Void)?

    init(engine: AnimationEngine) {
        self.engine = engine
        self.renderer = PresetRenderer()
        if renderer == nil {
            Log.overlay.error("Overlay disabled: no Metal device")
        }
        screenObserver = NotificationObserverToken(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.screensChanged() }
            }
        )
    }

    var captureIsAvailable: Bool {
        ScreenCapture.permissionState == .granted
    }

    func prewarm() {
        capture.prewarm()
    }

    func apply(_ transition: LidTransition, state: HingeState) {
        if transition.releaseCapture {
            releaseTexture()
        }
        if transition.hideOverlay {
            hideWindow()
        }
        if transition.requestCapture {
            primeCapture()
        }
        if transition.showOverlay {
            wantsWindowVisible = true
        }
        if transition.render {
            render(state)
        }
    }

    /// Fetches the desktop still ahead of the overlay being shown.
    ///
    /// Keyed off velocity alone. The animation only starts once the lid is well down,
    /// so waiting for progress to move would mean starting a screenshot at the exact
    /// moment the first frame is due. A closing lid announces itself long before then.
    func primeCaptureIfNeeded(progress: Double, velocity: Double) {
        guard velocity < Self.movementVelocity else {
            // A parked lid settles just short of fully open, so progress alone would
            // keep this primed forever and re-screenshot the desktop every couple of
            // seconds. Nothing is moving: let go of the image instead.
            if !wantsWindowVisible, captureTask == nil, hasTexture {
                releaseTexture()
            }
            return
        }
        primeCapture()
    }

    private func primeCapture() {
        guard engine.needsScreenCapture, captureIsAvailable else {
            // Non-capture presets have nothing to wait for.
            if !engine.needsScreenCapture { showWindowIfWanted() }
            return
        }
        guard captureTask == nil else { return }
        let isStale = MonotonicClock.now() - textureTimestamp > Self.captureMaxAge
        guard !hasTexture || isStale else { return }

        // The window is built now rather than on the first rendered frame, so the
        // capture and the window creation overlap instead of running back to back.
        ensureWindow()

        captureTask = Task { [weak self] in
            guard let self else { return }
            let image = await capture.captureBuiltInDisplay()
            guard !Task.isCancelled else { return }
            guard let image else {
                captureTask = nil
                return
            }
            await view?.uploadCapturedImage(image)
            guard !Task.isCancelled else { return }
            captureTask = nil
            hasTexture = true
            textureTimestamp = MonotonicClock.now()
            // Only reveal the overlay once it can draw something identical to what is
            // already on screen; showing it earlier would flash black.
            showWindowIfWanted()
        }
    }

    private func releaseTexture() {
        captureTask?.cancel()
        captureTask = nil
        view?.setCapturedImage(nil)
        hasTexture = false
        textureTimestamp = 0
    }

    private func render(_ state: HingeState) {
        let wasTracking = isTracking
        latestState = state
        isTracking = true
        if !wasTracking {
            // Start from where the lid actually is, or the overlay sweeps in from
            // whatever the animator was left holding.
            animator.reset(to: state.progress)
        }

        engine.context.captureAvailable = hasTexture || !engine.needsScreenCapture
        ensureWindow()
        let wasVisible = window?.isVisible ?? false
        showWindowIfWanted()
        if !wasVisible, window?.isVisible == true {
            // The frame the window appears with must be the current one. Deferring it
            // to the next refresh would show the panel a refresh behind the lid at the
            // exact moment the user first sees it.
            view?.renderImmediately(currentFrame())
        }
        view?.startDisplayLinkIfNeeded()
    }

    /// Advances the animation by one display refresh and evaluates the preset.
    private func frame(advancingBy interval: CFTimeInterval) -> FrameDescription? {
        guard isTracking else { return nil }
        animator.advance(
            target: latestState.progress,
            dt: interval,
            reportInterval: ProgressAnimator.denseSampleEase * 2
        )
        onProgressRendered?(animator.value)
        return currentFrame()
    }

    private func currentFrame() -> FrameDescription {
        engine.context.captureAvailable = hasTexture || !engine.needsScreenCapture
        var state = latestState
        state.progress = animator.value
        return engine.frame(for: state)
    }

    /// Renders one frame from an explicit progress value. Used by menu-bar preview.
    func renderPreview(progress: Double, direction: HingeDirection) {
        engine.context.captureAvailable = hasTexture || !engine.needsScreenCapture
        ensureWindow()
        wantsWindowVisible = true
        showWindowIfWanted()
        view?.submit(engine.frame(progress: progress, direction: direction))
    }

    #if DEBUG
    /// Installs a drawn stand-in for the desktop.
    ///
    /// Diagnostics have to measure the preset that is actually selected. Without a
    /// texture the engine substitutes Fade, which deforms nothing, so a trace would
    /// dutifully report a perfectly smooth animation of the wrong thing. Screen
    /// Recording is granted per bundle, and every build lands at a new path, so a
    /// diagnostic cannot rely on having it.
    func installStandInTexture() {
        ensureWindow()
        view?.setCapturedImage(PreviewImage.placeholder())
        hasTexture = true
        textureTimestamp = MonotonicClock.now()
    }
    #endif

    func prepareForPreview() {
        ensureWindow()
        primeCapture()
    }

    private func ensureWindow() {
        guard window == nil, let screen = DisplayManager.builtInScreen() else { return }
        let view = MetalPresetView(renderer: renderer)
        view.onFrameTiming = { [weak self] interval in self?.onFrameTiming?(interval) }
        view.onDisplayLinkTick = { [weak self] in self?.onDisplayLinkTick?() }
        view.frameProvider = { [weak self] interval in
            guard let frame = self?.frame(advancingBy: interval) else { return nil }
            self?.onFrameRendered?(frame)
            return frame
        }
        let window = OverlayWindow(screen: screen, contentView: view)
        self.view = view
        self.window = window
        Log.overlay.info("Overlay window created for the built-in display")
    }

    private func showWindowIfWanted() {
        guard wantsWindowVisible, let window else { return }
        guard !window.isVisible else { return }
        if engine.needsScreenCapture && captureIsAvailable && !hasTexture { return }
        window.orderFrontRegardless()
        view?.startDisplayLinkIfNeeded()
    }

    private func hideWindow() {
        wantsWindowVisible = false
        isTracking = false
        view?.stopDisplayLink()
        window?.orderOut(nil)
    }

    /// Tears the window down entirely, e.g. when the feature is switched off.
    func teardown() {
        hideWindow()
        releaseTexture()
        window = nil
        view = nil
    }

    private func screensChanged() {
        capture.invalidateCache()
        guard let screen = DisplayManager.builtInScreen() else {
            teardown()
            return
        }
        window?.matchGeometry(to: screen)
    }
}
