import Foundation
@testable import WatchLinkCore

public actor MockTransport: Transport {
    public var isReachable: Bool = true
    public private(set) var sentData: [Data] = []
    public var shouldFailOnSend = false

    private let dataStream: AsyncStream<IncomingMessage>
    private let dataContinuation: AsyncStream<IncomingMessage>.Continuation
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
        let (dataStream, dataContinuation) = AsyncStream<IncomingMessage>.makeStream()
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

    public func incoming() -> AsyncStream<IncomingMessage> {
        dataStream
    }

    public func start() async {}
    public func stop() async {
        dataContinuation.finish()
        reachabilityContinuation.finish()
        sentContinuation.finish()
    }

    public func simulateIncoming(_ data: Data, replyHandler: (@Sendable (Data) -> Void)? = nil) {
        dataContinuation.yield(IncomingMessage(data: data, replyHandler: replyHandler))
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
