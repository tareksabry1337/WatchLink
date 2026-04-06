import Testing
import Foundation
@testable import WatchLinkCore
import WatchLinkTestSupport

@Suite("Reply Handler")
struct ReplyHandlerTests {

    @Test("reply sends through reply handler AND transports")
    func replyFansOut() async throws {
        let transport = MockTransport()
        let coordinator = TransportCoordinator(transports: [transport])
        await coordinator.startAll()

        let mockReply = MockReplyHandler()
        let pingData = try encodeFrame(PingMessage(count: 1))
        await transport.simulateIncoming(pingData, replyHandler: mockReply.handler)

        let stream = await coordinator.messages(PingMessage.self)
        let received = try await firstValue(from: stream)

        let sentStream = await transport.onSent
        try await coordinator.reply(toFrameID: received.frameID, with: PongMessage(count: 1))

        #expect(mockReply.callCount == 1)

        let sentData: Data = try await firstValue(from: sentStream)
        #expect(!sentData.isEmpty)

        await coordinator.stopAll()
    }

    @Test("reply handler is correlated by frame ID")
    func replyCorrelation() async throws {
        let transport = MockTransport()
        let coordinator = TransportCoordinator(transports: [transport])
        await coordinator.startAll()

        let mockReply1 = MockReplyHandler()
        let mockReply2 = MockReplyHandler()

        let ping1Data = try encodeFrame(PingMessage(count: 1))
        let ping2Data = try encodeFrame(PingMessage(count: 2))

        await transport.simulateIncoming(ping1Data, replyHandler: mockReply1.handler)
        await transport.simulateIncoming(ping2Data, replyHandler: mockReply2.handler)

        let stream = await coordinator.messages(PingMessage.self)
        let msg1 = try await firstValue(from: stream)
        let msg2 = try await firstValue(from: stream)

        try await coordinator.reply(toFrameID: msg2.frameID, with: PongMessage(count: 22))
        try await coordinator.reply(toFrameID: msg1.frameID, with: PongMessage(count: 11))

        #expect(mockReply1.callCount == 1)
        #expect(mockReply2.callCount == 1)

        let pong1: PongMessage = try mockReply1.decodeFirstReply()
        let pong2: PongMessage = try mockReply2.decodeFirstReply()

        #expect(pong1.count == 11)
        #expect(pong2.count == 22)

        await coordinator.stopAll()
    }

    @Test("message without reply handler sends only through transports")
    func noReplyHandler() async throws {
        let transport = MockTransport()
        let coordinator = TransportCoordinator(transports: [transport])
        await coordinator.startAll()

        let pingData = try encodeFrame(PingMessage(count: 1))
        await transport.simulateIncoming(pingData)

        let stream = await coordinator.messages(PingMessage.self)
        let received = try await firstValue(from: stream)

        let sentStream = await transport.onSent
        try await coordinator.reply(toFrameID: received.frameID, with: PongMessage(count: 1))

        let sentData: Data = try await firstValue(from: sentStream)
        #expect(!sentData.isEmpty)

        await coordinator.stopAll()
    }

    @Test("reply handler is consumed once")
    func replyHandlerConsumedOnce() async throws {
        let transport = MockTransport()
        let coordinator = TransportCoordinator(transports: [transport])
        await coordinator.startAll()

        let mockReply = MockReplyHandler()
        let pingData = try encodeFrame(PingMessage(count: 1))
        await transport.simulateIncoming(pingData, replyHandler: mockReply.handler)

        let stream = await coordinator.messages(PingMessage.self)
        let received = try await firstValue(from: stream)

        try await coordinator.reply(toFrameID: received.frameID, with: PongMessage(count: 1))
        try await coordinator.reply(toFrameID: received.frameID, with: PongMessage(count: 2))

        #expect(mockReply.callCount == 1)

        await coordinator.stopAll()
    }

    @Test("send() does not use reply handlers")
    func plainSendIgnoresReplyHandlers() async throws {
        let transport = MockTransport()
        let coordinator = TransportCoordinator(transports: [transport])
        await coordinator.startAll()

        let mockReply = MockReplyHandler()
        let pingData = try encodeFrame(PingMessage(count: 1))
        await transport.simulateIncoming(pingData, replyHandler: mockReply.handler)

        let stream = await coordinator.messages(PingMessage.self)
        _ = try await firstValue(from: stream)

        let sentStream = await transport.onSent
        try await coordinator.send(PongMessage(count: 99))

        #expect(mockReply.callCount == 0)

        let sentData: Data = try await firstValue(from: sentStream)
        #expect(!sentData.isEmpty)

        await coordinator.stopAll()
    }
}
