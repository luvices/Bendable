import Foundation

enum HingeProviderError: Error, Equatable {
    case deviceUnavailable
    case openFailed(Int32)
}

/// A source of raw lid information.
///
/// Implementations must be safe to `start` and `stop` repeatedly and must never
/// keep the CPU busy while the lid is not moving.
protocol HingeProvider: AnyObject, Sendable {
    var capability: HingeCapability { get }

    /// Begins delivering samples. The handler may be called on any queue.
    func start(_ handler: @escaping @Sendable (HingeSample) -> Void) throws

    func stop()

    /// Re-establishes the hardware connection after a sleep/wake cycle.
    func reconnect()
}

extension HingeProvider {
    func reconnect() {}
}
