import Foundation
@testable import WatchLinkCore

public struct StreamEndedError: Error {
    public init() {}
}

public func firstValue<T: Sendable>(
    from stream: AsyncStream<T>,
    timeout: Duration = .seconds(30)
) async throws -> T {
    try await withTimeout(timeout) {
        for await value in stream { return value }
        throw StreamEndedError()
    }
}

public func firstMessage<M: WatchLinkMessage>(
    from stream: AsyncStream<ReceivedMessage<M>>,
    timeout: Duration = .seconds(30)
) async throws -> M {
    let received = try await firstValue(from: stream, timeout: timeout)
    return received.value
}

public func findFrame(
    from stream: AsyncStream<Data>,
    timeout: Duration = .seconds(30),
    matching predicate: @Sendable @escaping (Frame) -> Bool
) async throws -> Frame {
    try await withTimeout(timeout) {
        for await data in stream {
            if let frame = try? JSONDecoder().decode(Frame.self, from: data), predicate(frame) {
                return frame
            }
        }
        throw StreamEndedError()
    }
}

public func collectFrames(
    from stream: AsyncStream<Data>,
    count: Int,
    timeout: Duration = .seconds(30)
) async throws -> [Frame] {
    try await withTimeout(timeout) {
        var frames: [Frame] = []
        for await data in stream {
            if let frame = try? JSONDecoder().decode(Frame.self, from: data) {
                frames.append(frame)
                if frames.count >= count { return frames }
            }
        }
        return frames
    }
}
