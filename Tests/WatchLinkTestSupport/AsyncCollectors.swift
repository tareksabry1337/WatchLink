import Foundation

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
