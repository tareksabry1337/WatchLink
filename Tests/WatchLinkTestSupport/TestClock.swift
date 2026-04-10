import Foundation
@testable import WatchLinkCore

public final class TestClock: @unchecked Sendable {
    private struct Sleeper {
        let id: UUID
        let deadline: UInt64
        let continuation: CheckedContinuation<Void, any Error>
    }

    private let lock = NSLock()
    private var _now: UInt64 = 0
    private var sleepers: [Sleeper] = []

    public init() {}

    public var anyClock: AnyClock {
        AnyClock { [weak self] duration in
            guard let self else { return }
            try await self.sleep(for: duration)
        }
    }

    public func sleep(for duration: Duration) async throws {
        try Task.checkCancellation()

        let id = UUID()
        let deadline = lock.withLock { _now + duration.nanoseconds }

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
        } onCancel: { [weak self] in
            self?.lock.withLock {
                if let index = self?.sleepers.firstIndex(where: { $0.id == id }) {
                    let sleeper = self?.sleepers.remove(at: index)
                    sleeper?.continuation.resume(throwing: CancellationError())
                }
            }
        }
    }

    public func advance(by duration: Duration) {
        lock.withLock {
            _now += duration.nanoseconds
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
