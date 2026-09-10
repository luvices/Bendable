import Foundation
import IOKit.hid

/// Reads the built-in lid angle sensor present on Apple silicon MacBooks.
///
/// The sensor appears as a built-in HID device published by `AppleSPU` under the
/// product name `las`, on the HID Sensor usage page (0x20) with usage 0x8A. Nothing
/// here is privileged: no entitlement, no TCC prompt, no helper tool, no kernel
/// extension, and SIP is untouched.
///
/// The device has two ways of talking, and only one of them is any use for an
/// animation. It *pushes* an input report when the whole-degree angle changes, plus a
/// heartbeat about once a second. At hand speed that is a reading every forty or fifty
/// milliseconds, several display refreshes apart, and building an animation on it means
/// guessing what happened in between. But report 1 can also be *read* as a feature
/// report, which returns the angle as it is now, for about six tenths of a millisecond.
/// So the angle is polled at display rate while the lid is moving, and the pushed
/// reports are used only to notice that it has started.
///
/// Between movements the thread waits on a condition and costs nothing at all.
final class LidAngleSensorProvider: HingeProvider, @unchecked Sendable {
    private enum HID {
        static let vendorApple = 0x05AC
        static let sensorUsagePage = 0x20
        static let lidAngleUsage = 0x8A
        static let angleReportID: CFIndex = 1
        static let reportBufferSize = 16
    }

    /// About 144 Hz: at or above every display Apple ships, so a frame never has to
    /// draw an angle it was told about last time.
    private static let activeInterval: UInt32 = 6_900
    /// How long the lid must be still before the poll thread goes back to sleep.
    private static let idleAfter: TimeInterval = 1.2

    let capability: HingeCapability = .continuousAngle

    private let queue = DispatchQueue(label: "com.bendable.hinge.las.push", qos: .userInteractive)
    private let wakeUp = NSCondition()
    private var device: IOHIDDevice?
    private var reportBuffer = [UInt8](repeating: 0, count: HID.reportBufferSize)
    private var handler: (@Sendable (HingeSample) -> Void)?
    private var thread: Thread?
    private var isRunning = false
    private var isMoving = false

    static func isAvailable() -> Bool {
        copyDevice() != nil
    }

    private static func copyDevice() -> IOHIDDevice? {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [
            kIOHIDVendorIDKey: HID.vendorApple,
            kIOHIDPrimaryUsagePageKey: HID.sensorUsagePage,
            kIOHIDPrimaryUsageKey: HID.lidAngleUsage,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess,
              let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>
        else { return nil }
        return devices.first
    }

    func start(_ handler: @escaping @Sendable (HingeSample) -> Void) throws {
        guard !isRunning else { return }
        guard let device = Self.copyDevice() else { throw HingeProviderError.deviceUnavailable }

        let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else { throw HingeProviderError.openFailed(result) }

        self.device = device
        self.handler = handler
        isRunning = true

        // The pushed reports are not the data. They are the doorbell.
        let context = Unmanaged.passUnretained(self).toOpaque()
        reportBuffer.withUnsafeMutableBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            IOHIDDeviceRegisterInputReportCallback(
                device, base, buffer.count,
                { context, _, _, _, _, _, _ in
                    guard let context else { return }
                    Unmanaged<LidAngleSensorProvider>.fromOpaque(context)
                        .takeUnretainedValue()
                        .wake()
                },
                context
            )
        }
        IOHIDDeviceSetDispatchQueue(device, queue)
        IOHIDDeviceActivate(device)

        let thread = Thread { [weak self] in self?.poll() }
        thread.name = "com.bendable.hinge.las.poll"
        thread.qualityOfService = .userInteractive
        thread.start()
        self.thread = thread

        if let angle = readAngle() {
            handler(HingeSample(angle: angle, lidIsOpen: angle > 1))
        }
        Log.hinge.info("Lid angle sensor started")
    }

    func stop() {
        guard isRunning, let device else { return }
        isRunning = false
        wake()
        thread?.cancel()
        thread = nil
        IOHIDDeviceCancel(device)
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        self.device = nil
        handler = nil
        Log.hinge.info("Lid angle sensor stopped")
    }

    /// The SPU endpoint is torn down across system sleep; rebuild it on wake.
    func reconnect() {
        guard let handler else { return }
        let existing = handler
        stop()
        do {
            try start(existing)
        } catch {
            Log.hinge.error("Lid angle sensor reconnect failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func wake() {
        wakeUp.lock()
        isMoving = true
        wakeUp.signal()
        wakeUp.unlock()
    }

    private func poll() {
        var lastAngle = Double.nan
        var lastChange = MonotonicClock.now()

        while isRunning, !Thread.current.isCancelled {
            wakeUp.lock()
            while isRunning, !isMoving {
                wakeUp.wait()
            }
            wakeUp.unlock()
            guard isRunning else { return }

            guard let angle = readAngle() else {
                usleep(Self.activeInterval)
                continue
            }
            handler?(HingeSample(angle: angle, lidIsOpen: angle > 1))

            let now = MonotonicClock.now()
            if angle != lastAngle {
                lastAngle = angle
                lastChange = now
            } else if now - lastChange > Self.idleAfter {
                // Parked. Stop polling until the device rings the doorbell again.
                wakeUp.lock()
                isMoving = false
                wakeUp.unlock()
                continue
            }
            usleep(Self.activeInterval)
        }
    }

    /// Reads report 1 as a *feature* report, which answers with the angle as it is now.
    private func readAngle() -> Double? {
        guard let device else { return nil }
        var buffer = [UInt8](repeating: 0, count: HID.reportBufferSize)
        var length = buffer.count
        let status = IOHIDDeviceGetReport(
            device, kIOHIDReportTypeFeature, HID.angleReportID, &buffer, &length
        )
        guard status == kIOReturnSuccess else { return nil }
        return Self.parseAngle(bytes: buffer, length: length)
    }

    /// Report 1 is the report id followed by the angle in whole degrees, little-endian.
    static func parseAngle(bytes: [UInt8], length: Int) -> Double? {
        guard length >= 3, bytes[0] == UInt8(HID.angleReportID) else { return nil }
        let raw = Int16(bitPattern: UInt16(bytes[1]) | UInt16(bytes[2]) << 8)
        let degrees = Double(raw)
        guard HingeCalibration.plausibleRange.contains(degrees) else { return nil }
        return degrees
    }
}
