import Foundation

/// A monotonic point in time, unaffected by wall-clock changes.
///
/// Backed by `ProcessInfo.systemUptime`. Used by WatchLink's internal clock so
/// timers survive system clock adjustments.
public struct Instant: Sendable, Comparable, Hashable {
    let rawValue: TimeInterval

    /// The current monotonic instant.
    public static var now: Instant {
        Instant(rawValue: ProcessInfo.processInfo.systemUptime)
    }

    /// The duration from `self` to `other`.
    public func duration(to other: Instant) -> Duration {
        .seconds(other.rawValue - rawValue)
    }

    public static func - (lhs: Instant, rhs: Instant) -> Duration {
        rhs.duration(to: lhs)
    }

    public static func < (lhs: Instant, rhs: Instant) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
