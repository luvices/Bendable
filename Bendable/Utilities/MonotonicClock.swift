import Foundation

/// Seconds from a monotonic, sleep-inclusive source.
///
/// The hinge pipeline needs timestamps that survive display sleep and that can be
/// substituted in tests. `CLOCK_UPTIME_RAW` is unaffected by wall-clock adjustments,
/// which matters because a lid movement frequently straddles a sleep transition.
enum MonotonicClock {
    static func now() -> TimeInterval {
        TimeInterval(clock_gettime_nsec_np(CLOCK_UPTIME_RAW)) / 1_000_000_000
    }

    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    /// Converts a mach absolute timestamp, which is what IOKit stamps its reports with,
    /// into the same scale as `now()`.
    ///
    /// Using the sensor's own timestamp rather than the moment its callback happened to
    /// run keeps scheduling jitter out of the interval between samples, and therefore
    /// out of the velocity derived from it.
    static func seconds(fromMachAbsolute timestamp: UInt64) -> TimeInterval {
        guard timebase.denom != 0 else { return now() }
        let nanoseconds = Double(timestamp) * Double(timebase.numer) / Double(timebase.denom)
        return nanoseconds / 1_000_000_000
    }
}
