import Testing
import Foundation
@testable import WatchLinkCore
import WatchLinkTestSupport

@Suite("E2E Acknowledgments")
struct AckTests {

    // MARK: - Receiver sends ack

    @Test("receiver sends ack when message is received")
    func receiverSendsAck() async throws {
        let transport = MockTransport()
        let coordinator = TransportCoordinator(transports: [transport])
        await coordinator.startAll()

        let wireData = try encodeFrame(PingMessage(count: 1))
        let stream = await coordinator.messages(PingMessage.self)
        let sentStream = await transport.onSent

        await transport.simulateIncoming(wireData)
        _ = try await firstMessage(from: stream)

        // The coordinator should have sent an ack control frame back
        let ackData: Data = try await firstValue(from: sentStream)
        let ackFrame = try JSONDecoder().decode(Frame.self, from: ackData)
        #expect(ackFrame.kind == .control)

        let control = try JSONDecoder().decode(ControlFrame.self, from: ackFrame.payload)
        if case .ack(let ackedID) = control {
            // Decode the original frame to get its ID
            let originalFrame = try JSONDecoder().decode(Frame.self, from: wireData)
            #expect(ackedID == originalFrame.id)
        } else {
            Issue.record("Expected .ack, got \(control)")
        }

        await coordinator.stopAll()
    }

    @Test("duplicate message does not send a second ack")
    func duplicateDoesNotDoubleAck() async throws {
        let transport = MockTransport()
        let coordinator = TransportCoordinator(transports: [transport])
        await coordinator.startAll()

        let encoder = JSONEncoder()
        let frame = try Frame(wrapping: PingMessage(count: 1), encoder: encoder)
        let wireData = try encoder.encode(frame)

        let stream = await coordinator.messages(PingMessage.self)
        let sentStream = await transport.onSent

        // First arrival — should produce an ack
        await transport.simulateIncoming(wireData)
        _ = try await firstMessage(from: stream)
        let ackData: Data = try await firstValue(from: sentStream)

        let ackFrame = try JSONDecoder().decode(Frame.self, from: ackData)
        let control = try JSONDecoder().decode(ControlFrame.self, from: ackFrame.payload)
        if case .ack(let ackedID) = control {
            #expect(ackedID == frame.id)
        } else {
            Issue.record("Expected .ack, got \(control)")
        }

        // Second arrival (duplicate) — should NOT send another ack
        let sentBefore = await transport.sentData.count
        await transport.simulateIncoming(wireData)
        try await Task.sleep(for: .milliseconds(50))
        let sentAfter = await transport.sentData.count
        #expect(sentAfter == sentBefore)

        await coordinator.stopAll()
    }

    // MARK: - Sender tracks unacked

    @Test("send tracks message as unacked")
    func sendTracksUnacked() async throws {
        let transport = MockTransport()
        let coordinator = TransportCoordinator(transports: [transport])

        #expect(await coordinator.diagnosticsUnackedCount == 0)
        try await coordinator.send(PingMessage(count: 1))
        #expect(await coordinator.diagnosticsUnackedCount == 1)
        try await coordinator.send(PingMessage(count: 2))
        #expect(await coordinator.diagnosticsUnackedCount == 2)
    }

    @Test("ack removes message from unacked")
    func ackRemovesFromUnacked() async throws {
        let transport = MockTransport()
        let coordinator = TransportCoordinator(transports: [transport])
        await coordinator.startAll()

        // Send a message — captures its frame ID via the sent data
        let sentStream = await transport.onSent
        try await coordinator.send(PingMessage(count: 1))
        let sentData: Data = try await firstValue(from: sentStream)
        let sentFrame = try JSONDecoder().decode(Frame.self, from: sentData)

        #expect(await coordinator.diagnosticsUnackedCount == 1)

        // Simulate receiving an ack for that frame ID
        let encoder = JSONEncoder()
        let ackFrame = try Frame(control: .ack(sentFrame.id), encoder: encoder)
        let ackData = try encoder.encode(ackFrame)
        await transport.simulateIncoming(ackData)

        // Give the route a moment to process
        try await Task.sleep(for: .milliseconds(50))

        #expect(await coordinator.diagnosticsUnackedCount == 0)

        await coordinator.stopAll()
    }

    // MARK: - Control frames not acked

    @Test("control frames are not tracked as unacked")
    func controlFramesNotTracked() async throws {
        let transport = MockTransport()
        let coordinator = TransportCoordinator(transports: [transport])

        try await coordinator.sendControl(.ping)
        #expect(await coordinator.diagnosticsUnackedCount == 0)

        try await coordinator.sendControl(.pong)
        #expect(await coordinator.diagnosticsUnackedCount == 0)
    }

    @Test("ack control frames are not acked back — no infinite loop")
    func acksNotAcked() async throws {
        let transport = MockTransport()
        let coordinator = TransportCoordinator(transports: [transport])
        await coordinator.startAll()

        // Simulate receiving an ack — it should be handled internally, not forwarded
        let encoder = JSONEncoder()
        let ackFrame = try Frame(control: .ack("some-id"), encoder: encoder)
        let ackData = try encoder.encode(ackFrame)

        let sentBefore = await transport.sentData
        await transport.simulateIncoming(ackData)

        // Give route a moment to process
        try await Task.sleep(for: .milliseconds(50))

        // No ack should have been sent back (acks don't ack acks)
        let sentAfter = await transport.sentData
        #expect(sentAfter.count == sentBefore.count)

        await coordinator.stopAll()
    }

    @Test("ack is not forwarded to external control handler")
    func ackNotForwardedToHandler() async throws {
        let transport = MockTransport()
        let coordinator = TransportCoordinator(transports: [transport])
        let holder = ControlFrameHolder()

        await coordinator.onControl { frame in
            Task { await holder.append(frame) }
        }
        await coordinator.startAll()

        // Send a ping (should be forwarded) and an ack (should not)
        let encoder = JSONEncoder()

        let pingFrame = try Frame(control: .ping, encoder: encoder)
        await transport.simulateIncoming(try encoder.encode(pingFrame))

        let ackFrame = try Frame(control: .ack("some-id"), encoder: encoder)
        await transport.simulateIncoming(try encoder.encode(ackFrame))

        // Give route a moment to process both
        try await Task.sleep(for: .milliseconds(50))

        let received = await holder.frames
        #expect(received.count == 1)
        if case .ping = received.first {} else {
            Issue.record("Expected .ping, got \(String(describing: received.first))")
        }

        await coordinator.stopAll()
    }

    // MARK: - Retry

    @Test("retry loop resends unacked messages when reachable")
    func retryResends() async throws {
        let clock = TestClock()
        let transport = MockTransport()
        let coordinator = TransportCoordinator(
            transports: [transport],
            clock: AnyClock(clock),
            retryInterval: .seconds(5)
        )
        await coordinator.startAll()

        let sentStream = await transport.onSent
        try await coordinator.send(PingMessage(count: 1))

        // Consume the initial send
        _ = try await firstValue(from: sentStream)
        #expect(await coordinator.diagnosticsUnackedCount == 1)

        // Advance past retry interval — should resend
        clock.advance(by: .seconds(5))

        let retried: Data = try await firstValue(from: sentStream)
        #expect(!retried.isEmpty)
        // Still unacked (no ack received)
        #expect(await coordinator.diagnosticsUnackedCount == 1)

        await coordinator.stopAll()
    }

    @Test("retry loop skips when no transports are reachable")
    func retrySkipsWhenUnreachable() async throws {
        let clock = TestClock()
        let transport = MockTransport()
        await transport.setUnreachable()
        let coordinator = TransportCoordinator(
            transports: [transport],
            clock: AnyClock(clock),
            retryInterval: .seconds(5)
        )
        await coordinator.startAll()

        // Send while unreachable — goes to unacked but not sent
        try await coordinator.send(PingMessage(count: 1))
        let sentBefore = await transport.sentData
        #expect(sentBefore.isEmpty)

        // Advance past retry interval — still unreachable, should not attempt
        clock.advance(by: .seconds(5))
        try await Task.sleep(for: .milliseconds(50))

        let sentAfter = await transport.sentData
        #expect(sentAfter.isEmpty)

        await coordinator.stopAll()
    }

    @Test("reachability change triggers immediate retry of unacked messages")
    func reachabilityTriggersRetry() async throws {
        let transport = MockTransport()
        await transport.setUnreachable()
        let coordinator = TransportCoordinator(transports: [transport])
        await coordinator.startAll()

        try await coordinator.send(PingMessage(count: 1))
        let sent = await transport.sentData
        #expect(sent.isEmpty)

        // Become reachable — should immediately retry unacked
        let sentStream = await transport.onSent
        await transport.setReachable()

        let flushedData: Data = try await firstValue(from: sentStream)
        #expect(!flushedData.isEmpty)

        await coordinator.stopAll()
    }

    // MARK: - Sweep does not clear unacked

    @Test("sweep does not clear unacked messages")
    func sweepDoesNotClearUnacked() async throws {
        let clock = TestClock()
        let transport = MockTransport()
        let coordinator = TransportCoordinator(
            transports: [transport],
            clock: AnyClock(clock),
            sweepInterval: .seconds(30)
        )
        await coordinator.startAll()

        try await coordinator.send(PingMessage(count: 1))
        #expect(await coordinator.diagnosticsUnackedCount == 1)

        // Advance past sweep interval
        clock.advance(by: .seconds(30))
        try await Task.sleep(for: .milliseconds(50))

        // Unacked messages should survive the sweep
        #expect(await coordinator.diagnosticsUnackedCount == 1)

        await coordinator.stopAll()
    }

}

private actor ControlFrameHolder {
    var frames: [ControlFrame] = []

    func append(_ frame: ControlFrame) {
        frames.append(frame)
    }
}
