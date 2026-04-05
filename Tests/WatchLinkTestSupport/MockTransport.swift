import Foundation
@testable import WatchLinkCore

public actor MockTransport: Transport {
    public var isReachable: Bool = true
    public private(set) var sentData: [Data] = []
    public var shouldFailOnSend = false

    private let dataStream: AsyncStream<Data>
    private let dataContinuation: AsyncStream<Data>.Continuation
    private let reachabilityStream: AsyncStream<Bool>
    private let reachabilityContinuation: AsyncStream<Bool>.Continuation
    private let sentStream: AsyncStream<Data>
    private let sentContinuation: AsyncStream<Data>.Continuation

    public var reachabilityChanges: AsyncStream<Bool> {
        reachabilityStream
    }

    public var onSent: AsyncStream<Data> {
        sentStream
    }

    public init() {
        let (dataStream, dataContinuation) = AsyncStream<Data>.makeStream()
        self.dataStream = dataStream
        self.dataContinuation = dataContinuation

        let (reachabilityStream, reachabilityContinuation) = AsyncStream<Bool>.makeStream()
        self.reachabilityStream = reachabilityStream
        self.reachabilityContinuation = reachabilityContinuation

        let (sentStream, sentContinuation) = AsyncStream<Data>.makeStream()
        self.sentStream = sentStream
        self.sentContinuation = sentContinuation
    }

    public func send(_ data: Data) async throws {
        if shouldFailOnSend {
            throw WatchLinkError.sendFailed("Mock failure")
        }
        sentData.append(data)
        sentContinuation.yield(data)
    }

    public func incoming() -> AsyncStream<Data> {
        dataStream
    }

    public func start() async {}
    public func stop() async {
        dataContinuation.finish()
        reachabilityContinuation.finish()
        sentContinuation.finish()
    }

    public func simulateIncoming(_ data: Data) {
        dataContinuation.yield(data)
    }

    public func finishIncoming() {
        dataContinuation.finish()
    }

    public func setUnreachable() {
        isReachable = false
        reachabilityContinuation.yield(false)
    }

    public func setReachable() {
        isReachable = true
        reachabilityContinuation.yield(true)
    }

    public func setFailOnSend() { shouldFailOnSend = true }
}
