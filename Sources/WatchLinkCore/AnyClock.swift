import Foundation

package struct AnyClock: Sendable {
    private let _sleep: @Sendable (Duration) async throws -> Void

    package init() {
        _sleep = { duration in
            try await Task.sleep(nanoseconds: duration.nanoseconds)
        }
    }

    package init(sleep: @escaping @Sendable (Duration) async throws -> Void) {
        _sleep = sleep
    }

    package func sleep(for duration: Duration) async throws {
        try await _sleep(duration)
    }
}
