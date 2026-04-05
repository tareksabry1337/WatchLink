import Foundation

package struct AnyClock: Sendable {
    private let _sleep: @Sendable (Swift.Duration) async throws -> Void

    package init<C: Clock>(_ clock: C) where C.Duration == Swift.Duration {
        _sleep = { duration in
            try await clock.sleep(for: duration)
        }
    }

    package func sleep(for duration: Swift.Duration) async throws {
        try await _sleep(duration)
    }
}
