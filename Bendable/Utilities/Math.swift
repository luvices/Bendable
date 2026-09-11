import Foundation

@inlinable
func clamp<T: Comparable>(_ value: T, _ lower: T, _ upper: T) -> T {
    min(max(value, lower), upper)
}

@inlinable
func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
    a + (b - a) * t
}

/// Maps `value` from `from` into 0...1, clamped. Returns 0 for a degenerate range.
@inlinable
func normalize(_ value: Double, in range: ClosedRange<Double>) -> Double {
    let span = range.upperBound - range.lowerBound
    guard span > .ulpOfOne else { return 0 }
    return clamp((value - range.lowerBound) / span, 0, 1)
}

enum Easing {
    static func smoothstep(_ t: Double) -> Double {
        let x = clamp(t, 0, 1)
        return x * x * (3 - 2 * x)
    }

    static func easeInOutCubic(_ t: Double) -> Double {
        let x = clamp(t, 0, 1)
        return x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
    }

    static func easeOutQuad(_ t: Double) -> Double {
        let x = clamp(t, 0, 1)
        return 1 - (1 - x) * (1 - x)
    }

    /// Slow to start and still gaining at the end, for something falling away rather
    /// than being placed.
    static func easeInCubic(_ t: Double) -> Double {
        let x = clamp(t, 0, 1)
        return x * x * x
    }
}
