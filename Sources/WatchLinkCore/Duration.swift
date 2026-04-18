import Foundation

/// A time interval expressed in nanoseconds.
///
/// WatchLink ships its own `Duration` so the package can back-deploy to iOS 13 /
/// watchOS 7, which predate Swift's stdlib `Duration`.
public struct Duration: Sendable, Comparable, Hashable {
    /// The raw duration in nanoseconds.
    public let nanoseconds: UInt64

    /// Creates a duration from a raw nanosecond count.
    public init(nanoseconds: UInt64) {
        self.nanoseconds = nanoseconds
    }

    /// Creates a duration from a fractional number of seconds.
    public static func seconds(_ s: Double) -> Duration {
        Duration(nanoseconds: UInt64(s * 1_000_000_000))
    }

    /// Creates a duration from a whole number of seconds.
    public static func seconds(_ s: Int) -> Duration {
        Duration(nanoseconds: UInt64(s) * 1_000_000_000)
    }

    /// Creates a duration from a whole number of milliseconds.
    public static func milliseconds(_ ms: Int) -> Duration {
        Duration(nanoseconds: UInt64(ms) * 1_000_000)
    }

    /// A duration of zero.
    public static var zero: Duration { Duration(nanoseconds: 0) }

    /// The duration expressed as a `TimeInterval` (seconds).
    public var timeInterval: TimeInterval {
        Double(nanoseconds) / 1_000_000_000
    }

    public static func + (lhs: Duration, rhs: Duration) -> Duration {
        Duration(nanoseconds: lhs.nanoseconds + rhs.nanoseconds)
    }

    public static func * (lhs: Duration, rhs: Int) -> Duration {
        Duration(nanoseconds: lhs.nanoseconds * UInt64(rhs))
    }

    public static func * (lhs: Duration, rhs: Double) -> Duration {
        Duration(nanoseconds: UInt64(Double(lhs.nanoseconds) * rhs))
    }

    public static func < (lhs: Duration, rhs: Duration) -> Bool {
        lhs.nanoseconds < rhs.nanoseconds
    }
}
