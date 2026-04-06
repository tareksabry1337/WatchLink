import Testing
import Foundation
@testable import WatchLinkCore
import WatchLinkTestSupport

@Suite("TransportCoordinator")
struct TransportCoordinatorTests {

    // MARK: - Send

    @Test("send encodes message as a single Frame")
    func sendEncodesCorrectly() async throws {
        let transport = MockTransport()
        let coordinator = TransportCoordinator(transports: [transport])

        let sentStream = await transport.onSent
        try await coordinator.send(PingMessage(count: 42))

        let data: Data = try await firstValue(from: sentStream)
        let frame = try JSONDecoder().decode(Frame.self, from: data)
        #expect(frame.kind == .message)
        #expect(frame.channel == PingMessage.channel)

        let message = try JSONDecoder().decode(PingMessage.self, from: frame.payload)
        #expect(message.count == 42)
    }

    @Test("send queues when no transports are reachable and flushes on reachability")
    func sendQueuesWhenUnreachable() async throws {
        let transport = MockTransport()
        await transport.setUnreachable()
        let coordinator = TransportCoordinator(transports: [transport])
        await coordinator.startAll()

        try await coordinator.send(PingMessage(count: 1))

        let sent = await transport.sentData
        #expect(sent.isEmpty)

        let sentStream = await transport.onSent
        await transport.setReachable()

        let flushedData: Data = try await firstValue(from: sentStream)
        #expect(!flushedData.isEmpty)

        await coordinator.stopAll()
    }

    @Test("send succeeds if at least one transport succeeds")
    func sendSucceedsWithPartialFailure() async throws {
        let good = MockTransport()
        let bad = MockTransport()
        await bad.setFailOnSend()
        let coordinator = TransportCoordinator(transports: [good, bad])

        let sentStream = await good.onSent
        try await coordinator.send(PingMessage(count: 1))

        let data: Data = try await firstValue(from: sentStream)
        #expect(!data.isEmpty)
    }

    @Test("sendControl sends control frame")
    func sendControl() async throws {
        let transport = MockTransport()
        let coordinator = TransportCoordinator(transports: [transport])

        let sentStream = await transport.onSent
        try await coordinator.sendControl(.ping)

        let data: Data = try await firstValue(from: sentStream)
        let frame = try JSONDecoder().decode(Frame.self, from: data)
        #expect(frame.kind == .control)
    }

    // MARK: - Receive

    @Test("messages delivers typed messages for matching channel")
    func messagesDeliversTyped() async throws {
        let transport = MockTransport()
        let coordinator = TransportCoordinator(transports: [transport])
        await coordinator.startAll()

        let wireData = try encodeFrame(PingMessage(count: 99))

        let result: PingMessage = try await withTimeout(.seconds(2)) {
            let stream = await coordinator.messages(PingMessage.self)
            await transport.simulateIncoming(wireData)
            for await msg in stream { return msg.value }
            throw StreamEndedError()
        }

        #expect(result.count == 99)
        await coordinator.stopAll()
    }

    @Test("messages ignores messages for different channels")
    func messagesIgnoresDifferentChannel() async throws {
        let transport = MockTransport()
        let coordinator = TransportCoordinator(transports: [transport])
        await coordinator.startAll()

        let pongFrame = try encodeFrame(PongMessage(count: 1))
        let pingFrame = try encodeFrame(PingMessage(count: 7))

        let result: PingMessage = try await withTimeout(.seconds(2)) {
            let stream = await coordinator.messages(PingMessage.self)
            await transport.simulateIncoming(pongFrame)
            await transport.simulateIncoming(pingFrame)
            for await msg in stream { return msg.value }
            throw StreamEndedError()
        }

        #expect(result.count == 7)
        await coordinator.stopAll()
    }

    // MARK: - Deduplication

    @Test("duplicate messages are suppressed")
    func deduplication() async throws {
        let transport = MockTransport()
        let coordinator = TransportCoordinator(transports: [transport])
        await coordinator.startAll()

        let encoder = JSONEncoder()
        let duplicateFrame = try Frame(wrapping: PingMessage(count: 1), encoder: encoder)
        let duplicateData = try encoder.encode(duplicateFrame)
        let uniqueData = try encodeFrame(PingMessage(count: 2))

        let results = try await withTimeout(.seconds(2)) {
            let stream = await coordinator.messages(PingMessage.self)
            await transport.simulateIncoming(duplicateData)
            await transport.simulateIncoming(duplicateData)
            await transport.simulateIncoming(uniqueData)

            var collected: [PingMessage] = []
            for await msg in stream {
                collected.append(msg.value)
                if collected.count == 2 { break }
            }
            return collected
        }

        #expect(results.count == 2)
        #expect(results[0].count == 1)
        #expect(results[1].count == 2)
        await coordinator.stopAll()
    }

    // MARK: - Multiple Subscribers

    @Test("multiple subscribers to same channel each get every message")
    func multipleSubscribers() async throws {
        let transport = MockTransport()
        let coordinator = TransportCoordinator(transports: [transport])
        await coordinator.startAll()

        let wireData = try encodeFrame(PingMessage(count: 42))

        let stream1 = await coordinator.messages(PingMessage.self)
        let stream2 = await coordinator.messages(PingMessage.self)
        await transport.simulateIncoming(wireData)

        let r1: PingMessage = try await withTimeout(.seconds(2)) {
            for await msg in stream1 { return msg.value }
            throw StreamEndedError()
        }
        let r2: PingMessage = try await withTimeout(.seconds(2)) {
            for await msg in stream2 { return msg.value }
            throw StreamEndedError()
        }

        #expect(r1.count == 42)
        #expect(r2.count == 42)
        await coordinator.stopAll()
    }

    // MARK: - Control Frames

    @Test("control frames are dispatched to handler")
    func controlFrameDispatch() async throws {
        let transport = MockTransport()
        let coordinator = TransportCoordinator(transports: [transport])
        let holder = FrameHolder()

        await coordinator.onControl { frame in
            Task { await holder.set(frame) }
        }
        await coordinator.startAll()

        let encoder = JSONEncoder()
        let frame = try Frame(control: .ping, encoder: encoder)
        let data = try encoder.encode(frame)
        await transport.simulateIncoming(data)

        let receivedFrame: ControlFrame? = try await withTimeout(.seconds(2)) {
            await holder.next()
        }

        if case .ping = receivedFrame {} else {
            Issue.record("Expected .ping, got \(String(describing: receivedFrame))")
        }
        await coordinator.stopAll()
    }

    @Test("control frames are not delivered to message subscribers")
    func controlFramesNotDeliveredToMessages() async throws {
        let transport = MockTransport()
        let coordinator = TransportCoordinator(transports: [transport])
        await coordinator.startAll()

        let encoder = JSONEncoder()
        let controlFrame = try Frame(control: .ping, encoder: encoder)
        let controlData = try encoder.encode(controlFrame)
        let messageData = try encodeFrame(PingMessage(count: 1))

        let result: PingMessage = try await withTimeout(.seconds(2)) {
            let stream = await coordinator.messages(PingMessage.self)
            await transport.simulateIncoming(controlData)
            await transport.simulateIncoming(messageData)
            for await msg in stream { return msg.value }
            throw StreamEndedError()
        }

        #expect(result.count == 1)
        await coordinator.stopAll()
    }

}

private actor FrameHolder {
    private let stream: AsyncStream<ControlFrame>
    private let continuation: AsyncStream<ControlFrame>.Continuation

    init() {
        let (stream, continuation) = AsyncStream<ControlFrame>.makeStream()
        self.stream = stream
        self.continuation = continuation
    }

    func set(_ frame: ControlFrame) {
        continuation.yield(frame)
    }

    func next() async -> ControlFrame? {
        var iterator = stream.makeAsyncIterator()
        return await iterator.next()
    }
}
