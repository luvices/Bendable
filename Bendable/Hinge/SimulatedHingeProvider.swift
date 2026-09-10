import Foundation

/// Drives the pipeline from code instead of hardware.
///
/// Used by the preview scrubber, the debug panel, and the test suite, so the shipping
/// path and the developer path exercise the same normalizer and animation engine.
final class SimulatedHingeProvider: HingeProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable (HingeSample) -> Void)?
    private var _capability: HingeCapability
    private var _isConnected = true

    init(capability: HingeCapability = .continuousAngle) {
        _capability = capability
    }

    var capability: HingeCapability {
        lock.withLock { _capability }
    }

    func setCapability(_ capability: HingeCapability) {
        lock.withLock { _capability = capability }
    }

    var isConnected: Bool {
        get { lock.withLock { _isConnected } }
        set { lock.withLock { _isConnected = newValue } }
    }

    func start(_ handler: @escaping @Sendable (HingeSample) -> Void) throws {
        lock.withLock { self.handler = handler }
    }

    func stop() {
        lock.withLock { handler = nil }
    }

    func emit(angle: Double, at timestamp: TimeInterval = MonotonicClock.now()) {
        emit(HingeSample(angle: angle, lidIsOpen: angle > 1, timestamp: timestamp))
    }

    func emit(lidIsOpen: Bool, at timestamp: TimeInterval = MonotonicClock.now()) {
        emit(HingeSample(angle: nil, lidIsOpen: lidIsOpen, timestamp: timestamp))
    }

    func emit(_ sample: HingeSample) {
        let target = lock.withLock { _isConnected ? handler : nil }
        target?(sample)
    }
}
