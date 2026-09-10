@preconcurrency import Foundation
import IOKit
import IOKit.pwr_mgt

/// Fallback provider for Macs without a lid angle sensor.
///
/// `IOPMrootDomain` publishes `AppleClamshellState` and posts
/// `kIOPMMessageClamshellStateChange` as a general-interest notification on every lid
/// edge. That gives open/closed transitions with no polling, which is the most the
/// platform exposes on Intel Macs and on Apple silicon models without the sensor.
final class LidStateProvider: HingeProvider, @unchecked Sendable {
    /// `kIOPMMessageClamshellStateChange` is a macro, so it is unavailable to Swift.
    /// It expands to `iokit_family_msg(sub_iokit_powermanagement, 0x100)`.
    private static let clamshellStateChanged: UInt32 = {
        let systemIOKit: UInt32 = 0x38 << 26
        let subsystemPowerManagement: UInt32 = 13 << 14
        return systemIOKit | subsystemPowerManagement | 0x100
    }()

    let capability: HingeCapability = .lidStateOnly

    private var notifyPort: IONotificationPortRef?
    private var notification: io_object_t = 0
    private var rootDomain: io_service_t = 0
    private var handler: (@Sendable (HingeSample) -> Void)?
    private let queue = DispatchQueue(label: "com.bendable.hinge.lidstate", qos: .userInteractive)

    static func isAvailable() -> Bool {
        currentClamshellState() != nil
    }

    /// True when the lid is shut. `nil` on machines with no lid at all.
    static func currentClamshellState() -> Bool? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        return readClamshellState(from: service)
    }

    private static func readClamshellState(from service: io_service_t) -> Bool? {
        guard let property = IORegistryEntryCreateCFProperty(
            service, kAppleClamshellStateKey as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() else { return nil }
        return (property as? NSNumber)?.boolValue
    }

    func start(_ handler: @escaping @Sendable (HingeSample) -> Void) throws {
        guard notifyPort == nil else { return }

        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0, Self.readClamshellState(from: service) != nil else {
            if service != 0 { IOObjectRelease(service) }
            throw HingeProviderError.deviceUnavailable
        }
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else {
            IOObjectRelease(service)
            throw HingeProviderError.deviceUnavailable
        }

        self.handler = handler
        rootDomain = service
        notifyPort = port

        let context = Unmanaged.passUnretained(self).toOpaque()
        let result = IOServiceAddInterestNotification(
            port, service, kIOGeneralInterest,
            { context, _, messageType, _ in
                guard let context else { return }
                let provider = Unmanaged<LidStateProvider>.fromOpaque(context).takeUnretainedValue()
                provider.handleInterestMessage(messageType)
            },
            context, &notification
        )
        guard result == kIOReturnSuccess else {
            stop()
            throw HingeProviderError.openFailed(result)
        }

        IONotificationPortSetDispatchQueue(port, queue)
        emitCurrentState()
        Log.hinge.info("Lid state provider started")
    }

    func stop() {
        if notification != 0 {
            IOObjectRelease(notification)
            notification = 0
        }
        if let notifyPort {
            IONotificationPortDestroy(notifyPort)
            self.notifyPort = nil
        }
        if rootDomain != 0 {
            IOObjectRelease(rootDomain)
            rootDomain = 0
        }
        handler = nil
    }

    private func handleInterestMessage(_ messageType: UInt32) {
        guard messageType == Self.clamshellStateChanged else { return }
        emitCurrentState()
    }

    private func emitCurrentState() {
        guard let handler, rootDomain != 0,
              let clamshellClosed = Self.readClamshellState(from: rootDomain) else { return }
        handler(HingeSample(angle: nil, lidIsOpen: !clamshellClosed))
    }
}
