import Foundation

/// Where the lid is, as far as the overlay is concerned.
enum LidPhase: String, Sendable, Equatable {
    /// Open and parked. Nothing rendered, no display link, no capture held.
    case idle
    /// Moving. The overlay is up and following the hinge.
    case tracking
    /// Effectively shut, drawn fully dark, waiting to see whether the Mac sleeps.
    case nearlyClosed
    /// Shut while the Mac keeps running on an external display.
    case clamshell
    case sleeping
    /// Awake again but not yet resynchronised with the sensor.
    case waking
}

/// Actions the coordinator should take, returned rather than performed so the
/// transition table stays testable.
struct LidTransition: Sendable, Equatable {
    var phase: LidPhase
    var showOverlay = false
    var hideOverlay = false
    /// Take a fresh still of the desktop before the next frame.
    var requestCapture = false
    /// Drop the held desktop image. Always done before sleeping.
    var releaseCapture = false
    var render = false
}

/// Explicit transition table for the lid lifecycle.
///
/// Lid notifications, display power changes and sleep do not arrive in a fixed order,
/// and closing the lid does not always mean sleeping, since clamshell mode with an
/// external display keeps the Mac awake. Keeping this as one function makes the ordering
/// assumptions visible and lets the tests drive every path.
struct LidStateMachine {
    /// Openness below which a close is considered underway.
    ///
    /// Deliberately close to 1: the overlay has to already be up and showing an image
    /// indistinguishable from the desktop by the time the fold becomes perceptible,
    /// otherwise it appears part-way through the movement and reads as lag. At this
    /// threshold the panel has rotated well under a degree. Filtered sensor dither
    /// stays inside the remaining margin.
    static let engageThreshold = 0.997
    /// Openness above which the overlay is torn down again. Hysteresis against the
    /// engage threshold keeps a parked lid from cycling the window.
    static let disengageThreshold = 0.9995
    /// Openness at or below which the panel is treated as shut.
    static let closedThreshold = 0.02

    private(set) var phase: LidPhase = .idle
    /// True when an external display is attached, which is what makes clamshell possible.
    var externalDisplayAttached = false
    var animatesClosing = true
    var animatesOpening = true
    var isEnabled = true

    mutating func reset() {
        phase = .idle
    }

    mutating func handle(_ state: HingeState) -> LidTransition {
        guard isEnabled else { return leave(to: .idle) }

        switch phase {
        case .idle:
            guard state.progress < Self.engageThreshold else { return stay() }
            guard directionIsAnimated(state.direction) else { return stay() }
            return enterTracking(requestCapture: true)

        case .tracking:
            // Either wide open, or open enough and no longer moving. The second case
            // matters because filtered readings settle just short of the top of the
            // calibrated range, so waiting for the hard threshold alone can leave the
            // overlay up indefinitely.
            if state.progress >= Self.disengageThreshold
                || (state.progress >= Self.engageThreshold && state.direction == .still) {
                return leave(to: .idle)
            }
            if state.progress <= Self.closedThreshold {
                return LidTransition(phase: assign(.nearlyClosed), render: true)
            }
            if !directionIsAnimated(state.direction) && state.direction != .still {
                return leave(to: .idle)
            }
            return LidTransition(phase: .tracking, render: true)

        case .nearlyClosed:
            if state.progress > Self.closedThreshold {
                // Reopened before the Mac slept: pick straight back up mid-animation.
                return LidTransition(phase: assign(.tracking), render: true)
            }
            return stay()

        case .clamshell:
            if state.progress > Self.closedThreshold {
                return enterTracking(requestCapture: true)
            }
            return stay()

        case .sleeping:
            return stay()

        case .waking:
            if state.progress >= Self.disengageThreshold {
                return leave(to: .idle)
            }
            guard animatesOpening else { return leave(to: .idle) }
            return LidTransition(phase: assign(.tracking), showOverlay: true, requestCapture: true, render: true)
        }
    }

    mutating func handle(_ event: PowerEvent) -> LidTransition {
        switch event {
        case .systemWillSleep, .displaysDidSleep:
            // Stop drawing immediately and drop the desktop image: it must not survive
            // into a locked session.
            if phase == .sleeping { return stay() }
            let next: LidPhase = (event == .displaysDidSleep && phase == .nearlyClosed
                && externalDisplayAttached) ? .clamshell : .sleeping
            return LidTransition(phase: assign(next), releaseCapture: true)

        case .systemDidWake, .displaysDidWake:
            guard phase == .sleeping || phase == .clamshell else { return stay() }
            return LidTransition(phase: assign(.waking))

        case .screenLocked:
            return LidTransition(phase: phase, releaseCapture: true)

        case .screenUnlocked:
            return stay()
        }
    }

    mutating func setEnabled(_ enabled: Bool) -> LidTransition {
        isEnabled = enabled
        return enabled ? stay() : leave(to: .idle)
    }

    private func directionIsAnimated(_ direction: HingeDirection) -> Bool {
        switch direction {
        case .closing: animatesClosing
        case .opening: animatesOpening
        case .still: true
        }
    }

    private mutating func assign(_ next: LidPhase) -> LidPhase {
        if phase != next {
            Log.trace(Log.power, "lid phase \(self.phase.rawValue) -> \(next.rawValue)")
        }
        phase = next
        return next
    }

    private mutating func enterTracking(requestCapture: Bool) -> LidTransition {
        LidTransition(
            phase: assign(.tracking), showOverlay: true, requestCapture: requestCapture, render: true
        )
    }

    private mutating func leave(to next: LidPhase) -> LidTransition {
        LidTransition(phase: assign(next), hideOverlay: true, releaseCapture: true)
    }

    private func stay() -> LidTransition {
        LidTransition(phase: phase)
    }
}
