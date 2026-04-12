import Foundation

package final class SafeContinuation<T: Sendable>: @unchecked Sendable {
    private let continuation: CheckedContinuation<T, Error>
    private var hasResumed = false
    private let lock = NSLock()

    package init(_ continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
    }

    package func resume(returning value: T) {
        lock.lock()
        guard !hasResumed else {
            lock.unlock()
            return
        }
        hasResumed = true
        lock.unlock()
        continuation.resume(returning: value)
    }

    package func resume(throwing error: Error) {
        lock.lock()
        guard !hasResumed else {
            lock.unlock()
            return
        }
        hasResumed = true
        lock.unlock()
        continuation.resume(throwing: error)
    }
}
