import Foundation

public struct Duration: Sendable, Comparable, Hashable {
    public let nanoseconds: UInt64

    public init(nanoseconds: UInt64) {
        self.nanoseconds = nanoseconds
    }

    public static func seconds(_ s: Double) -> Duration {
        Duration(nanoseconds: UInt64(s * 1_000_000_000))
    }

    public static func seconds(_ s: Int) -> Duration {
        Duration(nanoseconds: UInt64(s) * 1_000_000_000)
    }

    public static func milliseconds(_ ms: Int) -> Duration {
        Duration(nanoseconds: UInt64(ms) * 1_000_000)
    }

    public static var zero: Duration { Duration(nanoseconds: 0) }

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
