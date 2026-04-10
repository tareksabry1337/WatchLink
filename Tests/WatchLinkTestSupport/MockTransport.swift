import Foundation
@testable import WatchLinkCore

public struct RecordedReply: Sendable {
    public let frameID: String
    public let data: Data
}

public actor MockTransport: Transport {
    public var isReachable: Bool = true
    public private(set) var sentData: [Data] = []
    public private(set) var replies: [RecordedReply] = []
    public var shouldFailOnSend = false
    public var shouldFailOnRequest = false

    private let dataStream: AsyncStream<IncomingMessage>
    private let dataContinuation: AsyncStream<IncomingMessage>.Continuation
    private let reachabilityStream: AsyncStream<Bool>
    private let reachabilityContinuation: AsyncStream<Bool>.Continuation
    private let sentStream: AsyncStream<Data>
    private let sentContinuation: AsyncStream<Data>.Continuation
    private var requestContinuations: [String: CheckedContinuation<Data, Error>] = [:]

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

    public func simulateIncoming(_ data: Data) {
        dataContinuation.yield(IncomingMessage(data: data))
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

    public func populateDiagnostics(_ diagnostics: inout WatchLinkDiagnostics) async {}
    public func request(_ data: Data) async throws -> Data {
        if shouldFailOnRequest {
            throw WatchLinkError.sendFailed("Mock request failure")
        }

        sentData.append(data)
        sentContinuation.yield(data)

        let frame = try JSONDecoder().decode(Frame.self, from: data)
        let frameID = frame.id

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                requestContinuations[frameID] = continuation
            }
        } onCancel: { [weak self] in
            Task { await self?.cancelPendingRequest(frameID) }
        }
    }

    public func simulateRequestReply(to frameID: String, with data: Data) {
        requestContinuations.removeValue(forKey: frameID)?.resume(returning: data)
    }

    private func cancelPendingRequest(_ frameID: String) {
        requestContinuations.removeValue(forKey: frameID)?.resume(throwing: CancellationError())
    }

    public func reply(to frameID: String, with data: Data) async {
        replies.append(RecordedReply(frameID: frameID, data: data))
    }

    public func setFailOnSend() { shouldFailOnSend = true }
    public func setFailOnRequest() { shouldFailOnRequest = true }
}
