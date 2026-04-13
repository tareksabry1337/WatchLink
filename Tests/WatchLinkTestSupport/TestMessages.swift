import Foundation
@testable import WatchLinkCore

public struct PingMessage: WatchLinkMessage {
    public let count: Int
    public init(count: Int) { self.count = count }
}

public struct PongMessage: WatchLinkMessage {
    public let count: Int
    public init(count: Int) { self.count = count }
}

public struct AskMessage: WatchLinkMessage {
    public typealias Response = AnswerMessage
    public let question: String
    public init(question: String) { self.question = question }
}

public struct AnswerMessage: WatchLinkMessage {
    public let answer: String
    public init(answer: String) { self.answer = answer }
}

public func encodeFrame<M: WatchLinkMessage>(_ message: M, confirmedAcks: [String] = []) throws -> Data {
    let encoder = JSONEncoder()
    let frame = try Frame(wrapping: message, encoder: encoder, confirmedAcks: confirmedAcks)
    return try encoder.encode(frame)
}

public func encodeControlFrame(_ control: ControlFrame, confirmedAcks: [String] = []) throws -> Data {
    let encoder = JSONEncoder()
    let frame = try Frame(control: control, encoder: encoder, confirmedAcks: confirmedAcks)
    return try encoder.encode(frame)
}

public struct StreamEndedError: Error {
    public init() {}
}

public func firstValue<T: Sendable>(
    from stream: AsyncStream<T>,
    timeout: Duration = .seconds(2)
) async throws -> T {
    try await withTimeout(timeout) {
        for await value in stream { return value }
        throw StreamEndedError()
    }
}

public func firstMessage<M: WatchLinkMessage>(
    from stream: AsyncStream<ReceivedMessage<M>>,
    timeout: Duration = .seconds(2)
) async throws -> M {
    let received = try await firstValue(from: stream, timeout: timeout)
    return received.value
}

public actor AsyncCollector<T: Sendable> {
    public private(set) var values: [T] = []
    public var count: Int { values.count }
    public init() {}
    public func append(_ value: T) { values.append(value) }
}

public actor AsyncHolder<T: Sendable> {
    private let stream: AsyncStream<T>
    private let continuation: AsyncStream<T>.Continuation

    public init() {
        let (stream, continuation) = AsyncStream<T>.makeStream()
        self.stream = stream
        self.continuation = continuation
    }

    public func send(_ value: T) {
        continuation.yield(value)
    }

    public func next() async -> T? {
        var iterator = stream.makeAsyncIterator()
        return await iterator.next()
    }
}

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
