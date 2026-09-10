import AppKit
import Foundation
import Observation

/// Wires the hinge pipeline, the power monitor, the state machine and the overlay.
///
/// This is the only object that knows about all of them; each piece below it is
/// independently testable.
@MainActor
@Observable
final class AppCoordinator {
    let preferences: Preferences
    let state = AppState()

    @ObservationIgnored private let hinge = HingeService()
    @ObservationIgnored private let power = PowerMonitor()
    @ObservationIgnored private let engine: AnimationEngine
    @ObservationIgnored private let overlay: OverlayCoordinator
    @ObservationIgnored private var machine = LidStateMachine()
    @ObservationIgnored private var previewTask: Task<Void, Never>?
    @ObservationIgnored private var lastDiagnosticsPublish: TimeInterval = 0
    @ObservationIgnored private var lastCalibrationPublish: HingeCalibration = .default

    /// Diagnostics are read by a human, and a human cannot read 125 updates a second.
    /// The animation path below never touches observable state at all.
    private static let diagnosticsInterval = 1.0 / 10
    @ObservationIgnored private var settingsObservation: Task<Void, Never>?
    @ObservationIgnored private var accessibilityObserver: NotificationObserverToken?

    init(preferences: Preferences = Preferences()) {
        self.preferences = preferences
        self.engine = AnimationEngine(preset: AnimationPresetCatalog.preset(id: preferences.presetID))
        self.overlay = OverlayCoordinator(engine: engine)
    }

    func start() {
        Log.verboseEnabled = preferences.debugLogging
        applySettings()

        hinge.calibration = preferences.calibration
        hinge.onStateChange = { [weak self] state in self?.handle(state) }
        hinge.start()

        power.onEvent = { [weak self] event in self?.handle(event) }
        power.start()

        overlay.onFrameTiming = { [weak self] interval in self?.publishFrameInterval(interval) }

        state.capability = hinge.capability
        state.launchAtLoginEnabled = LaunchAtLogin.isEnabled
        state.calibration = hinge.calibration
        refreshScreenCapturePermission()

        observeSettings()
        accessibilityObserver = NotificationObserverToken(
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.applySettings() }
            },
            center: NSWorkspace.shared.notificationCenter
        )
        Log.app.info("Bendable started with capability \(self.state.capability.rawValue, privacy: .public)")
    }

    func stop() {
        accessibilityObserver = nil
        settingsObservation?.cancel()
        previewTask?.cancel()
        hinge.stop()
        power.stop()
        overlay.teardown()
    }

    // MARK: - Settings

    /// Re-reads every setting the engine and state machine depend on.
    func applySettings() {
        engine.select(presetID: preferences.presetID)
        engine.context.closingIntensity = preferences.closingIntensity
        engine.context.openingIntensity = preferences.openingIntensity
        engine.context.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        engine.context.capability = hinge.capability
        engine.context.captureAvailable = ScreenCapture.permissionState == .granted
        engine.context.tuning = preferences.currentTuning
        state.isSubstitutingPreset = engine.isSubstituting
        if let screen = DisplayManager.builtInScreen() {
            engine.context.screenSize = SIMD2(Float(screen.frame.width), Float(screen.frame.height))
            engine.context.scaleFactor = screen.backingScaleFactor
        }

        machine.animatesClosing = preferences.animatesClosing
        machine.animatesOpening = preferences.animatesOpening
        machine.externalDisplayAttached = DisplayManager.hasExternalDisplay
        hinge.smoothing = preferences.smoothing
        hinge.animationStartAngle = preferences.startAngle
        state.animationRange = hinge.animationRange
        engine.context.hingeTravelDegrees = max(
            hinge.animationRange.upperBound - hinge.animationRange.lowerBound, 10
        )
        Log.verboseEnabled = preferences.debugLogging

        let transition = machine.setEnabled(preferences.enabled)
        overlay.apply(transition, state: hinge.state)
        state.phase = machine.phase
    }

    /// Observation-driven: any preference change re-applies settings once.
    private func observeSettings() {
        settingsObservation?.cancel()
        settingsObservation = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                await withCheckedContinuation { continuation in
                    withObservationTracking {
                        guard let self else { return }
                        _ = (
                            self.preferences.enabled, self.preferences.presetID,
                            self.preferences.closingIntensity, self.preferences.openingIntensity,
                            self.preferences.smoothing, self.preferences.animatesClosing,
                            self.preferences.animatesOpening, self.preferences.debugLogging,
                            self.preferences.currentTuning, self.preferences.startAngle
                        )
                    } onChange: {
                        continuation.resume()
                    }
                }
                guard let self, !Task.isCancelled else { return }
                applySettings()
            }
        }
    }

    // MARK: - Pipeline

    private func handle(_ hingeState: HingeState) {
        guard previewTask == nil else {
            publishDiagnostics(hingeState)
            return
        }

        // The animation path first, and with nothing observable in it.
        overlay.primeCaptureIfNeeded(progress: hingeState.progress, velocity: hingeState.velocity)
        let transition = machine.handle(hingeState)
        overlay.apply(transition, state: hingeState)

        // Phase changes are rare, so publishing them immediately costs nothing.
        if state.phase != transition.phase {
            state.phase = transition.phase
        }
        publishDiagnostics(hingeState)
    }

    private func publishDiagnostics(_ hingeState: HingeState) {
        let now = MonotonicClock.now()
        guard now - lastDiagnosticsPublish >= Self.diagnosticsInterval else { return }
        lastDiagnosticsPublish = now

        state.hinge = hingeState
        state.rawAngle = hinge.rawAngle
        state.sensorRate = hinge.updateRate

        // The open reference drifts continuously, so persisting on any change would
        // rewrite user defaults constantly. A degree either way is well below what the
        // animation can show.
        let calibration = hinge.calibration
        if abs(calibration.openAngle - lastCalibrationPublish.openAngle) > 1
            || abs(calibration.closedAngle - lastCalibrationPublish.closedAngle) > 1 {
            lastCalibrationPublish = calibration
            state.calibration = calibration
            preferences.calibration = calibration
            let range = hinge.animationRange
            state.animationRange = range
            engine.context.hingeTravelDegrees = max(range.upperBound - range.lowerBound, 10)
        }
    }

    private func publishFrameInterval(_ interval: Double) {
        let now = MonotonicClock.now()
        guard now - lastDiagnosticsPublish >= Self.diagnosticsInterval else { return }
        lastDiagnosticsPublish = now
        state.frameInterval = interval
    }

    private func handle(_ event: PowerEvent) {
        switch event {
        case .systemDidWake, .displaysDidWake:
            // The sensor endpoint does not survive system sleep; rebuild it before
            // relying on the next reading.
            hinge.reconnect()
            machine.externalDisplayAttached = DisplayManager.hasExternalDisplay
        case .systemWillSleep:
            previewTask?.cancel()
            previewTask = nil
        default:
            break
        }
        let transition = machine.handle(event)
        overlay.apply(transition, state: hinge.state)
        state.phase = transition.phase
    }

    // MARK: - Actions

    /// Runs the selected preset over the whole travel on the real display.
    func runPreview() {
        previewTask?.cancel()
        overlay.prepareForPreview()
        previewTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let duration = 1.2
            let start = MonotonicClock.now()
            var elapsed = 0.0
            while elapsed < duration * 2, !Task.isCancelled {
                elapsed = MonotonicClock.now() - start
                let phase = elapsed / duration
                let progress = phase < 1
                    ? 1 - Easing.easeInOutCubic(phase)
                    : Easing.easeInOutCubic(phase - 1)
                overlay.renderPreview(
                    progress: clamp(progress, 0, 1), direction: phase < 1 ? .closing : .opening
                )
                try? await Task.sleep(for: .milliseconds(8))
            }
            overlay.renderPreview(progress: 1, direction: .opening)
            overlay.teardown()
            previewTask = nil
        }
    }

    func requestScreenCapturePermission() {
        ScreenCapture.requestPermission()
        refreshScreenCapturePermission()
    }

    /// Re-reads the TCC state.
    ///
    /// Permission can be granted or revoked in System Settings at any time, and macOS
    /// tells the app nothing when it happens. Cached at launch, the app would keep
    /// silently rendering the fallback preset long after the user had allowed it, which
    /// looks exactly like the chosen preset being broken.
    func refreshScreenCapturePermission() {
        let granted = ScreenCapture.permissionState == .granted
        let changed = granted != state.screenCaptureGranted
        state.screenCaptureGranted = granted
        engine.context.captureAvailable = granted
        state.isSubstitutingPreset = engine.isSubstituting
        guard changed else { return }
        Log.capture.info("Screen recording permission is now \(granted ? "granted" : "absent", privacy: .public)")
        if granted {
            overlay.prewarm()
        }
    }

    /// Relaunches the app.
    ///
    /// Screen Recording is only re-evaluated for a process at launch, so granting it to
    /// a running Bendable often does nothing until it starts again.
    func relaunch() {
        let url = Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            if let error {
                Log.app.error("Relaunch failed: \(error.localizedDescription, privacy: .public)")
                return
            }
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLogin.set(enabled)
            state.launchAtLoginProblem = nil
        } catch {
            Log.app.error("Launch at login change failed: \(String(describing: error), privacy: .public)")
            state.launchAtLoginProblem = error.localizedDescription
        }
        state.launchAtLoginEnabled = LaunchAtLogin.isEnabled
    }

    func resetCalibration() {
        preferences.resetCalibration()
        hinge.resetCalibration()
        state.calibration = hinge.calibration
    }

    /// Builds an engine bound to the current settings for the settings-window preview,
    /// so the scrubber renders through exactly the same code path as the lid.
    func makePreviewEngine() -> AnimationEngine {
        let previewEngine = AnimationEngine(
            preset: AnimationPresetCatalog.preset(id: preferences.presetID), context: engine.context
        )
        return previewEngine
    }

    // MARK: - Debug support

    #if DEBUG
    @ObservationIgnored private(set) var simulator: SimulatedHingeProvider?

    func setTraceHooks(
        onTick: (() -> Void)?,
        onFrame: ((FrameDescription) -> Void)?,
        onProgress: ((Double) -> Void)? = nil
    ) {
        overlay.onDisplayLinkTick = onTick
        overlay.onFrameRendered = onFrame
        overlay.onProgressRendered = onProgress
    }

    /// Pins the preset for a diagnostic run, so a trace measures a known thing rather
    /// than whatever happens to be selected.
    func forcePreset(_ id: String) {
        engine.select(presetID: id)
    }

    func currentAnimationRange() -> ClosedRange<Double> {
        hinge.animationRange
    }

    func installStandInTexture() {
        overlay.installStandInTexture()
    }

    /// What the engine is actually drawing, which is not always what was chosen.
    func renderedPresetID() -> String {
        engine.effectivePreset.id
    }

    /// Replaces the hardware provider with the simulator so the whole pipeline can be
    /// driven from the debug pane.
    func useSimulatedHinge(_ enabled: Bool) {
        hinge.stop()
        if enabled {
            let provider = SimulatedHingeProvider()
            simulator = provider
            hinge.start(provider: provider)
        } else {
            simulator = nil
            hinge.start()
        }
        state.capability = hinge.capability
    }

    func injectPowerEvent(_ event: PowerEvent) {
        power.emit(event)
    }
    #endif
}
