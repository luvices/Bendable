import Foundation

/// Removes a block-based notification observer when the owner goes away.
///
/// Block observers do not retain their owner, so without this the observer outlives
/// whatever registered it. Doing the removal in this object's own `deinit` keeps the
/// cleanup off the owner's isolated `deinit`.
final class NotificationObserverToken: @unchecked Sendable {
    private let token: any NSObjectProtocol
    private let center: NotificationCenter

    init(_ token: any NSObjectProtocol, center: NotificationCenter = .default) {
        self.token = token
        self.center = center
    }

    deinit {
        center.removeObserver(token)
    }
}
