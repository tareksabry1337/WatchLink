import Foundation

public struct Instant: Sendable, Comparable, Hashable {
    let rawValue: TimeInterval

    public static var now: Instant {
        Instant(rawValue: ProcessInfo.processInfo.systemUptime)
    }

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
