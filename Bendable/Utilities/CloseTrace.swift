#if DEBUG
import AppKit
import Foundation

/// Drives a simulated close through the real pipeline and reports what actually
/// happened, so the smoothness of the result can be measured rather than guessed at.
///
/// Reachable from `Bendable --trace-close`. It puts the real overlay on the built-in
/// display for about a second, because the display link only runs for a window that is
/// actually on screen, which is itself one of the things worth checking.
@MainActor
enum CloseTrace {
    /// The sensor's ceiling. It only actually speaks when the angle crosses a whole
    /// degree, which is what the simulation reproduces.
    private static let sensorInterval = 1.0 / 144

    static func run(coordinator: AppCoordinator, closeDuration: Double = 0.7) async -> String {
        var ticks = 0
        var rendered: [FrameDescription] = []
        var tracked: [Double] = []
        var tickTimes: [TimeInterval] = []
        coordinator.setTraceHooks(
            onTick: { ticks += 1; tickTimes.append(MonotonicClock.now()) },
            onFrame: { rendered.append($0) },
            onProgress: { tracked.append($0) }
        )
        coordinator.forcePreset(FoldPreset.id)
        coordinator.useSimulatedHinge(true)
        coordinator.installStandInTexture()
        guard let simulator = coordinator.simulator else { return "no simulator" }

        let start = coordinator.currentAnimationRange().upperBound + 25
        // Settle at the resting angle so the reference and the state machine agree
        // about where the lid is before anything moves.
        var clock = MonotonicClock.now()
        for _ in 0..<12 {
            clock += 0.02
            simulator.emit(angle: start, at: clock)
            try? await Task.sleep(for: .milliseconds(20))
        }

        // Everything up to here is the lid sitting still. Counting it would report the
        // settle as frozen frames and make every ratio meaningless.
        rendered.removeAll()
        tracked.removeAll()
        tickTimes.removeAll()
        ticks = 0

        let sampleCount = Int(closeDuration / sensorInterval)
        var samples = 0
        var lastEmitted = start
        var noise: UInt64 = 0x2545F4914F6CDD1D
        var firstMovementAt: TimeInterval?
        let restingTilt = rendered.last?.foldAngle ?? 0
        for step in 0...sampleCount {
            let fraction = Double(step) / Double(sampleCount)
            clock += sensorInterval
            // The sensor reports whole degrees, and only when that integer changes,
            // so a slowly moving lid is heard from far less often than the sample rate
            // suggests. Reproducing that is the entire point of the exercise.
            // Real quantisation is not a clean staircase: a lid held between two whole
            // degrees dithers across the boundary, so the reported integer sometimes
            // goes back before it goes on. A simulation without that flatters any
            // estimator that differences consecutive readings.
            let trueAngle = start * (1 - fraction)
            // Deterministic so runs are comparable, but without the structure a sine
            // would impose. Sampled near Nyquist a sine aliases into runs and troughs
            // that no real sensor produces, and the smoothing gets judged on those.
            noise = noise &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let dither = (Double(noise >> 11) / Double(UInt64(1) << 53) - 0.5) * 0.7
            let angle = (trueAngle + dither).rounded()
            // The sensor is polled, so a reading arrives every time round whether or
            // not the whole degree has changed. That is the point of polling.
            simulator.emit(angle: angle, at: clock)
            if angle != lastEmitted { lastEmitted = angle }
            // From the first reading that should move anything, not the first reading
            // at all. Time spent crossing the dead zone is by design.
            if firstMovementAt == nil, coordinator.state.hinge.progress < 0.999 {
                firstMovementAt = MonotonicClock.now()
            }
            samples += 1
            try? await Task.sleep(for: .microseconds(Int(sensorInterval * 1_000_000)))
        }
        // Then stop dead, mid-movement, and keep watching. A lid that has been let go
        // of must stop with it. The sensor keeps up its heartbeat, so silence is not an
        // excuse to carry on.
        let trackedAtStop = tracked.count
        let valueAtStop = tracked.last ?? 0
        var heartbeat = clock
        for _ in 0..<8 {
            heartbeat += 0.12
            simulator.emit(angle: lastEmitted, at: heartbeat)
            try? await Task.sleep(for: .milliseconds(120))
        }
        let driftAfterStop = abs((tracked.last ?? valueAtStop) - valueAtStop) * 100
        let framesAfterStop = tracked.count - trackedAtStop

        // How long after the lid first moved did anything appear on screen.
        var onset = "n/a"
        if let firstMovementAt,
           let respondedAt = zip(tickTimes, rendered).first(where: {
               abs($0.1.foldAngle - restingTilt) > 0.002
           })?.0 {
            onset = String(format: "%.0f ms", (respondedAt - firstMovementAt) * 1000)
        }

        // Smoothness is a property of the tracked value, whatever the preset does with
        // it. Expressed as a percentage of the whole travel so the numbers mean the
        // same thing at any band width, and measured only while the lid was actually
        // moving, since frames after it stopped are all stalls by definition.
        let moving = Array(tracked.prefix(trackedAtStop))
        let trackedSteps = zip(moving, moving.dropFirst()).map { abs($1 - $0) * 100 }
        let trackedMean = trackedSteps.isEmpty
            ? 0 : trackedSteps.reduce(0, +) / Double(trackedSteps.count)
        let trackedWorst = trackedSteps.max() ?? 0
        let evenness = trackedMean > 0 ? trackedWorst / trackedMean : 0
        let trackedStalls = trackedSteps.filter { $0 < 0.002 }.count

        let tilts = rendered.map { $0.foldAngle * 180 / .pi }
        let steps = zip(tilts, tilts.dropFirst()).map { abs($1 - $0) }
        // Frames where nothing moved at all: the animation frozen, waiting to be told
        // something. This is what slow movement felt like.
        let stalled = steps.filter { $0 < 0.001 }.count
        let largest = steps.max() ?? 0
        let largestIndex = steps.firstIndex(of: largest) ?? 0
        let mean = steps.isEmpty ? 0 : steps.reduce(0, +) / Double(steps.count)

        let intervals = zip(tickTimes, tickTimes.dropFirst()).map { ($1 - $0) * 1000 }
        let longestInterval = intervals.max() ?? 0
        let dropped = intervals.filter { $0 > 25 }.count
        // A step is only judder if it is out of line with its neighbours; a fast lid
        // legitimately moves a long way in one frame.
        let ratios = zip(steps, steps.dropFirst()).map { $0 > 0.01 ? $1 / $0 : 1 }
        let worstRatio = ratios.max() ?? 1

        coordinator.setTraceHooks(onTick: nil, onFrame: nil)
        coordinator.useSimulatedHinge(false)

        return [
            "calibration: closed \(String(format: "%.1f", coordinator.state.calibration.closedAngle))° resting \(String(format: "%.1f", coordinator.state.calibration.openAngle))° start setting \(String(format: "%.0f", coordinator.preferences.startAngle))°",
            "band: \(String(format: "%.1f", coordinator.currentAnimationRange().lowerBound))° to \(String(format: "%.1f", coordinator.currentAnimationRange().upperBound))°",
            "preset rendered: \(coordinator.renderedPresetID())",
            "tracked step: mean \(String(format: "%.3f", trackedMean))% worst \(String(format: "%.3f", trackedWorst))% of travel",
            "tracked stalls: \(trackedStalls) of \(trackedSteps.count) while moving",
            "evenness (worst / mean step): \(String(format: "%.2f", evenness))x",
            "drift after the lid stopped: \(String(format: "%.2f", driftAfterStop))% of travel over \(framesAfterStop) frames",
            "sensor samples: \(samples)",
            "display link ticks: \(ticks)",
            "frames rendered: \(rendered.count)",
            "tilt travelled: \(String(format: "%.1f", (tilts.max() ?? 0) - (tilts.min() ?? 0)))°",
            "largest step: \(String(format: "%.2f", largest))° at frame \(largestIndex) of \(steps.count)",
            "mean step: \(String(format: "%.3f", mean))°",
            "onset latency: \(onset)",
            "hinge at end: angle \(coordinator.state.hinge.angle.map { String(format: "%.1f", $0) } ?? "nil")° progress \(String(format: "%.3f", coordinator.state.hinge.progress)) velocity \(String(format: "%.2f", coordinator.state.hinge.velocity))",
            "raw at end: \(coordinator.state.rawAngle.map { String(format: "%.1f", $0) } ?? "nil")°",
            "tilt range: \(String(format: "%.2f", tilts.min() ?? 0))° to \(String(format: "%.2f", tilts.max() ?? 0))°",
            "worst neighbour ratio: \(String(format: "%.2f", worstRatio))x",
            "frozen frames: \(stalled) of \(steps.count)",
            "longest frame interval: \(String(format: "%.1f", longestInterval)) ms",
            "intervals over 25 ms: \(dropped)",
            "first five steps: " + steps.prefix(5).map { String(format: "%.2f", $0) }.joined(separator: ", "),
        ].joined(separator: "\n")
    }
}
#endif
