import XCTest
@testable import Bendable

final class HingeProviderTests: XCTestCase {
    /// Provider callbacks arrive on the sensor's queue, so test state is boxed rather
    /// than captured as locals.
    private final class Collector: @unchecked Sendable {
        private let lock = NSLock()
        private var normalizer = HingeNormalizer(
            calibration: HingeCalibration(closedAngle: 0, openAngle: 120), smoothing: 0.2, autoCalibrates: false
        )
        private var states: [HingeState] = []

        func ingest(_ sample: HingeSample) {
            lock.withLock {
                if let state = normalizer.normalize(sample) { states.append(state) }
            }
        }

        var received: [HingeState] { lock.withLock { states } }
    }

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func increment() { lock.withLock { count += 1 } }
        var value: Int { lock.withLock { count } }
    }

    func testSimulatorFeedsTheNormalizer() {
        let provider = SimulatedHingeProvider()
        let collector = Collector()
        try? provider.start { collector.ingest($0) }

        var time: TimeInterval = 0
        for angle in stride(from: 120.0, through: 0.0, by: -10.0) {
            time += 0.02
            provider.emit(angle: angle, at: time)
        }

        let received = collector.received
        XCTAssertEqual(received.count, 13)
        XCTAssertEqual(received.last?.direction, .closing)
        XCTAssertTrue(received.last?.isClosed ?? false)
    }

    func testDisconnectingTheSensorStopsDelivery() {
        let provider = SimulatedHingeProvider()
        let counter = Counter()
        try? provider.start { _ in counter.increment() }

        provider.emit(angle: 90, at: 1)
        provider.isConnected = false
        provider.emit(angle: 45, at: 2)
        provider.isConnected = true
        provider.emit(angle: 30, at: 3)

        XCTAssertEqual(counter.value, 2)
    }

    func testStoppingDetachesTheHandler() {
        let provider = SimulatedHingeProvider()
        let counter = Counter()
        try? provider.start { _ in counter.increment() }
        provider.emit(angle: 90, at: 1)
        provider.stop()
        provider.emit(angle: 45, at: 2)
        XCTAssertEqual(counter.value, 1)
    }

    func testLidAngleReportsAreParsed() {
        // 104° = 0x68, little-endian after the report id.
        XCTAssertEqual(LidAngleSensorProvider.parseAngle(bytes: [0x01, 0x68, 0x00], length: 3), 104)
        XCTAssertEqual(LidAngleSensorProvider.parseAngle(bytes: [0x01, 0x86, 0x00], length: 3), 134)
        XCTAssertEqual(LidAngleSensorProvider.parseAngle(bytes: [0x01, 0x00, 0x00], length: 3), 0)
    }

    func testMalformedOrImplausibleReportsAreRejected() {
        // Wrong report id.
        XCTAssertNil(LidAngleSensorProvider.parseAngle(bytes: [0x02, 0x68, 0x00], length: 3))
        // Too short to hold an angle.
        XCTAssertNil(LidAngleSensorProvider.parseAngle(bytes: [0x01], length: 1))
        // Beyond anything a lid can reach.
        XCTAssertNil(LidAngleSensorProvider.parseAngle(bytes: [0x01, 0xC8, 0x01], length: 3))
        // Negative, which the sensor emits while it is still working out where it is.
        XCTAssertNil(LidAngleSensorProvider.parseAngle(bytes: [0x01, 0xFF, 0xFF], length: 3))
    }

    func testCapabilityDescriptionsAreDistinct() {
        let descriptions = Set(HingeCapability.allCases.map(\.localizedDescription))
        XCTAssertEqual(descriptions.count, HingeCapability.allCases.count)
    }
}
