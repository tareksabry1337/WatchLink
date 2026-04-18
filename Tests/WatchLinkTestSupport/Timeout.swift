import Foundation
@testable import WatchLinkCore

public struct TestTimeoutError: Error {
    public init() {}
}

public func withTimeout<T: Sendable>(
    _ duration: Duration,
    operation: @Sendable @escaping () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: duration.nanoseconds)
            throw TestTimeoutError()
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
