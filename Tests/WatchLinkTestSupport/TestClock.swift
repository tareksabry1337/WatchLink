import Foundation
@testable import WatchLinkCore

public final class TestClock: Clock, @unchecked Sendable {
    public struct Instant: InstantProtocol, Hashable, Sendable {
        public var offset: Duration

        public func advanced(by duration: Duration) -> Instant {
            Instant(offset: offset + duration)
        }

        public func duration(to other: Instant) -> Duration {
            other.offset - offset
        }

        public static func < (lhs: Instant, rhs: Instant) -> Bool {
            lhs.offset < rhs.offset
        }
    }

    private struct Sleeper {
        let id: UUID
        let deadline: Instant
        let continuation: CheckedContinuation<Void, any Error>
    }

    private let lock = NSLock()
    private var _now: Instant = Instant(offset: .zero)
    private var sleepers: [Sleeper] = []

    public var now: Instant {
        lock.withLock { _now }
    }

    public var minimumResolution: Duration { .zero }

    public init() {}

    public func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        try Task.checkCancellation()

        let id = UUID()

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.withLock {
                    if _now >= deadline {
                        continuation.resume()
                    } else {
                        sleepers.append(Sleeper(id: id, deadline: deadline, continuation: continuation))
                    }
                }
            }
        } onCancel: {
            lock.withLock {
                if let index = sleepers.firstIndex(where: { $0.id == id }) {
                    let sleeper = sleepers.remove(at: index)
                    sleeper.continuation.resume(throwing: CancellationError())
                }
            }
        }
    }

    public func advance(by duration: Duration) {
        lock.withLock {
            _now = _now.advanced(by: duration)
            let ready = sleepers.filter { $0.deadline <= _now }
            sleepers.removeAll { $0.deadline <= _now }
            for sleeper in ready {
                sleeper.continuation.resume()
            }
        }
    }

    public var pendingSleepCount: Int {
        lock.withLock { sleepers.count }
    }
}
