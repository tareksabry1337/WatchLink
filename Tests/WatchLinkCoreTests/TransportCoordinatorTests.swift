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
        let duplicateFrame = try Frame(wrapping: PingMessage(count: 1), encoder: encoder, confirmedAcks: [])
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

    // MARK: - Request / Reply

    @Test("send with Response type returns decoded response from transport")
    func sendWithResponse() async throws {
        let transport = MockTransport()
        let coordinator = TransportCoordinator(transports: [transport])
        await coordinator.startAll()

        let responseData = try JSONEncoder().encode(AnswerMessage(answer: "42"))
        let sentStream = await transport.onSent

        let response: AnswerMessage = try await withTimeout(.seconds(2)) {
            async let result = coordinator.send(AskMessage(question: "meaning"), timeout: .seconds(5))

            let sent = try await firstValue(from: sentStream)
            let frame = try JSONDecoder().decode(Frame.self, from: sent)
            await transport.simulateRequestReply(to: frame.id, with: responseData)

            return try await result
        }

        #expect(response.answer == "42")
        await coordinator.stopAll()
    }

    @Test("request succeeds when one transport fails and another replies")
    func requestSucceedsWithPartialFailure() async throws {
        let good = MockTransport()
        let bad = MockTransport()
        await bad.setFailOnRequest()
        let coordinator = TransportCoordinator(transports: [bad, good])
        await coordinator.startAll()

        let responseData = try JSONEncoder().encode(AnswerMessage(answer: "ok"))
        let sentStream = await good.onSent

        let response: AnswerMessage = try await withTimeout(.seconds(2)) {
            async let result = coordinator.send(AskMessage(question: "test"), timeout: .seconds(5))

            let sent = try await firstValue(from: sentStream)
            let frame = try JSONDecoder().decode(Frame.self, from: sent)
            await good.simulateRequestReply(to: frame.id, with: responseData)

            return try await result
        }

        #expect(response.answer == "ok")
        await coordinator.stopAll()
    }

    @Test("request times out when all transports fail")
    func requestTimesOutWhenAllFail() async throws {
        let bad1 = MockTransport()
        let bad2 = MockTransport()
        await bad1.setFailOnRequest()
        await bad2.setFailOnRequest()
        let coordinator = TransportCoordinator(transports: [bad1, bad2])
        await coordinator.startAll()

        do {
            let _: AnswerMessage = try await coordinator.send(
                AskMessage(question: "hello"),
                timeout: .milliseconds(100)
            )
            Issue.record("Expected requestTimedOut error")
        } catch is WatchLinkError {
            // expected
        }

        await coordinator.stopAll()
    }

    @Test("first transport to reply wins in multi-transport request")
    func firstReplyWins() async throws {
        let fast = MockTransport()
        let slow = MockTransport()
        let coordinator = TransportCoordinator(transports: [fast, slow])
        await coordinator.startAll()

        let fastSentStream = await fast.onSent

        let response: AnswerMessage = try await withTimeout(.seconds(2)) {
            async let result = coordinator.send(AskMessage(question: "race"), timeout: .seconds(5))

            let sent = try await firstValue(from: fastSentStream)
            let frame = try JSONDecoder().decode(Frame.self, from: sent)
            let fastReply = try JSONEncoder().encode(AnswerMessage(answer: "fast"))
            await fast.simulateRequestReply(to: frame.id, with: fastReply)

            return try await result
        }

        #expect(response.answer == "fast")
        await coordinator.stopAll()
    }

    @Test("send with Response type times out if no reply")
    func sendWithResponseTimesOut() async throws {
        let transport = MockTransport()
        let coordinator = TransportCoordinator(transports: [transport])
        await coordinator.startAll()

        do {
            let _: AnswerMessage = try await coordinator.send(
                AskMessage(question: "hello"),
                timeout: .milliseconds(100)
            )
            Issue.record("Expected requestTimedOut error")
        } catch is WatchLinkError {
            // expected
        }

        await coordinator.stopAll()
    }

    @Test("reply routes to transport with correct frameID and data")
    func replyRoutesToTransport() async throws {
        let transport = MockTransport()
        let coordinator = TransportCoordinator(transports: [transport])
        await coordinator.startAll()

        let wireData = try encodeFrame(AskMessage(question: "time?"))
        let frame = try JSONDecoder().decode(Frame.self, from: wireData)

        let received: ReceivedMessage<AskMessage> = try await withTimeout(.seconds(2)) {
            let stream = await coordinator.messages(AskMessage.self)
            await transport.simulateIncoming(wireData)
            for await msg in stream { return msg }
            throw StreamEndedError()
        }

        try await coordinator.reply(with: AnswerMessage(answer: "now"), to: received.frameID)

        let replies = await transport.replies
        #expect(replies.count == 1)
        #expect(replies[0].frameID == frame.id)

        let decoded = try JSONDecoder().decode(AnswerMessage.self, from: replies[0].data)
        #expect(decoded.answer == "now")

        await coordinator.stopAll()
    }

    // MARK: - Control Frames

    @Test("control frames are dispatched to handler")
    func controlFrameDispatch() async throws {
        let transport = MockTransport()
        let coordinator = TransportCoordinator(transports: [transport])
        let holder = AsyncHolder<ControlFrame>()

        await coordinator.onControl { frame in
            Task { await holder.send(frame) }
        }
        await coordinator.startAll()

        let encoder = JSONEncoder()
        let frame = try Frame(control: .ping, encoder: encoder, confirmedAcks: [])
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
        let controlFrame = try Frame(control: .ping, encoder: encoder, confirmedAcks: [])
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

    // MARK: - Ack-of-Ack

    @Test("receiving ack queues confirmation, next outgoing frame carries it")
    func ackConfirmationPiggybacked() async throws {
        let transport = MockTransport()
        let coordinator = TransportCoordinator(transports: [transport])
        await coordinator.startAll()

        // Send message X, capture its frame ID
        let sentStream = await transport.onSent
        try await coordinator.send(PingMessage(count: 1))
        let sentData: Data = try await firstValue(from: sentStream)
        let sentFrame = try JSONDecoder().decode(Frame.self, from: sentData)
        let messageID = sentFrame.id

        // Simulate ack, then a marker message to prove ack was processed
        let ackData = try encodeControlFrame(.ack(messageID))
        let markerData = try encodeFrame(PongMessage(count: 999))
        let markerStream = await coordinator.messages(PongMessage.self)
        await transport.simulateIncoming(ackData)
        await transport.simulateIncoming(markerData)
        _ = try await firstMessage(from: markerStream)

        // Send another message — should carry confirmation for messageID
        let sentStream2 = await transport.onSent
        try await coordinator.send(PingMessage(count: 2))
        let nextData: Data = try await firstValue(from: sentStream2)
        let nextFrame = try JSONDecoder().decode(Frame.self, from: nextData)

        #expect(nextFrame.confirmedAcks.contains(messageID))

        await coordinator.stopAll()
    }

    @Test("confirmations piggybacked on control frames")
    func confirmationOnControlFrame() async throws {
        let transport = MockTransport()
        let coordinator = TransportCoordinator(transports: [transport])
        await coordinator.startAll()

        // Send message, capture ID
        let sentStream = await transport.onSent
        try await coordinator.send(PingMessage(count: 1))
        let sentData: Data = try await firstValue(from: sentStream)
        let sentFrame = try JSONDecoder().decode(Frame.self, from: sentData)

        // Simulate ack + marker to sync
        let ackData = try encodeControlFrame(.ack(sentFrame.id))
        let markerData = try encodeFrame(PongMessage(count: 999))
        let markerStream = await coordinator.messages(PongMessage.self)
        await transport.simulateIncoming(ackData)
        await transport.simulateIncoming(markerData)
        _ = try await firstMessage(from: markerStream)

        // Send a control frame — should carry the confirmation
        let sentStream2 = await transport.onSent
        try await coordinator.sendControl(.ping)
        let pingData: Data = try await firstValue(from: sentStream2)
        let pingFrame = try JSONDecoder().decode(Frame.self, from: pingData)

        #expect(pingFrame.confirmedAcks.contains(sentFrame.id))

        await coordinator.stopAll()
    }

    @Test("receiving confirmedAcks removes IDs from seenIDs")
    func confirmedAcksRemovesFromSeenIDs() async throws {
        let transport = MockTransport()
        let coordinator = TransportCoordinator(transports: [transport])
        await coordinator.startAll()

        // Simulate incoming message — adds to seenIDs
        let messageData = try encodeFrame(PingMessage(count: 1))
        let frame = try JSONDecoder().decode(Frame.self, from: messageData)
        let pingStream = await coordinator.messages(PingMessage.self)
        await transport.simulateIncoming(messageData)
        _ = try await firstMessage(from: pingStream)

        #expect(await coordinator.diagnosticsSeenIDsCount == 1)

        // Simulate incoming frame with confirmedAcks for that message ID
        // Use a marker on PongMessage channel to sync
        let confirmData = try encodeFrame(PongMessage(count: 1), confirmedAcks: [frame.id])
        let pongStream = await coordinator.messages(PongMessage.self)
        await transport.simulateIncoming(confirmData)
        _ = try await firstMessage(from: pongStream)

        // seenIDs has 1 entry (PongMessage's own ID), not 2 — confirmation removed the original
        #expect(await coordinator.diagnosticsSeenIDsCount == 1)

        await coordinator.stopAll()
    }

    @Test("pending confirmations flushed after being sent")
    func confirmationsFlushedAfterSend() async throws {
        let transport = MockTransport()
        let coordinator = TransportCoordinator(transports: [transport])
        await coordinator.startAll()

        // Send message, get ack
        let sentStream = await transport.onSent
        try await coordinator.send(PingMessage(count: 1))
        let sentData: Data = try await firstValue(from: sentStream)
        let sentFrame = try JSONDecoder().decode(Frame.self, from: sentData)

        // Simulate ack + marker to sync
        let ackData = try encodeControlFrame(.ack(sentFrame.id))
        let markerData = try encodeFrame(PongMessage(count: 999))
        let markerStream = await coordinator.messages(PongMessage.self)
        await transport.simulateIncoming(ackData)
        await transport.simulateIncoming(markerData)
        _ = try await firstMessage(from: markerStream)

        // First send carries confirmations
        let sentStream2 = await transport.onSent
        try await coordinator.send(PingMessage(count: 2))
        let firstData: Data = try await firstValue(from: sentStream2)
        let firstFrame = try JSONDecoder().decode(Frame.self, from: firstData)
        #expect(!firstFrame.confirmedAcks.isEmpty)

        // Second send should have empty confirmations — already flushed
        let sentStream3 = await transport.onSent
        try await coordinator.send(PingMessage(count: 3))
        let secondData: Data = try await firstValue(from: sentStream3)
        let secondFrame = try JSONDecoder().decode(Frame.self, from: secondData)
        #expect(secondFrame.confirmedAcks.isEmpty)

        await coordinator.stopAll()
    }

    @Test("multiple ack confirmations batched in single frame")
    func multipleConfirmationsBatched() async throws {
        let transport = MockTransport()
        let coordinator = TransportCoordinator(transports: [transport])
        await coordinator.startAll()

        let sentStream = await transport.onSent

        // Send two messages
        try await coordinator.send(PingMessage(count: 1))
        let data1: Data = try await firstValue(from: sentStream)
        let frame1 = try JSONDecoder().decode(Frame.self, from: data1)

        let sentStream2 = await transport.onSent
        try await coordinator.send(PingMessage(count: 2))
        let data2: Data = try await firstValue(from: sentStream2)
        let frame2 = try JSONDecoder().decode(Frame.self, from: data2)

        // Simulate acks for both + marker to sync
        let ack1 = try encodeControlFrame(.ack(frame1.id))
        let ack2 = try encodeControlFrame(.ack(frame2.id))
        let markerData = try encodeFrame(PongMessage(count: 999))
        let markerStream = await coordinator.messages(PongMessage.self)
        await transport.simulateIncoming(ack1)
        await transport.simulateIncoming(ack2)
        await transport.simulateIncoming(markerData)
        _ = try await firstMessage(from: markerStream)

        // Next outgoing frame should carry both confirmations
        let sentStream3 = await transport.onSent
        try await coordinator.send(PingMessage(count: 3))
        let batchData: Data = try await firstValue(from: sentStream3)
        let batchFrame = try JSONDecoder().decode(Frame.self, from: batchData)

        #expect(batchFrame.confirmedAcks.contains(frame1.id))
        #expect(batchFrame.confirmedAcks.contains(frame2.id))

        await coordinator.stopAll()
    }

    @Test("retried message always gets re-acked")
    func retriedMessageReAcked() async throws {
        let transport = MockTransport()
        let coordinator = TransportCoordinator(transports: [transport])
        await coordinator.startAll()

        let encoder = JSONEncoder()
        let messageFrame = try Frame(wrapping: PingMessage(count: 1), encoder: encoder, confirmedAcks: [])
        let messageData = try encoder.encode(messageFrame)

        let stream = await coordinator.messages(PingMessage.self)

        // First delivery — wait for message to arrive at subscriber
        await transport.simulateIncoming(messageData)
        _ = try await firstMessage(from: stream)

        // Wait for the ack to be sent by listening on onSent
        let sentStream = await transport.onSent
        let ackSent: Data = try await firstValue(from: sentStream)
        let ackFrame = try JSONDecoder().decode(Frame.self, from: ackSent)
        #expect(ackFrame.kind == .control)

        let acksAfterFirst = await transport.sentData.count

        // Simulate retry of same frame — should re-ack but not re-deliver
        // Use a marker on PongMessage to detect when processing is done
        let markerData = try encodeFrame(PongMessage(count: 999))
        let markerStream = await coordinator.messages(PongMessage.self)
        await transport.simulateIncoming(messageData)
        await transport.simulateIncoming(markerData)
        _ = try await firstMessage(from: markerStream)

        let acksAfterRetry = await transport.sentData.count
        #expect(acksAfterRetry > acksAfterFirst, "Retried message should trigger another ack")

        await coordinator.stopAll()
    }

    @Test("control frames are not deduped")
    func controlFramesNotDeduped() async throws {
        let transport = MockTransport()
        let coordinator = TransportCoordinator(transports: [transport])
        let holder = AsyncHolder<ControlFrame>()

        await coordinator.onControl { frame in
            Task { await holder.send(frame) }
        }
        await coordinator.startAll()

        let encoder = JSONEncoder()
        let pingFrame = try Frame(control: .ping, encoder: encoder, confirmedAcks: [])
        let pingData = try encoder.encode(pingFrame)

        // Send same control frame twice — both should be processed
        await transport.simulateIncoming(pingData)
        let first = try await withTimeout(.seconds(2)) { await holder.next() }

        await transport.simulateIncoming(pingData)
        let second = try await withTimeout(.seconds(2)) { await holder.next() }

        if case .ping = first {} else { Issue.record("Expected ping") }
        if case .ping = second {} else { Issue.record("Expected ping on retry") }

        await coordinator.stopAll()
    }

    @Test("control frame IDs do not accumulate in seenIDs")
    func controlFrameIDsDontAccumulate() async throws {
        let transport = MockTransport()
        let coordinator = TransportCoordinator(transports: [transport])
        let holder = AsyncHolder<ControlFrame>()

        await coordinator.onControl { frame in
            Task { await holder.send(frame) }
        }
        await coordinator.startAll()

        // Send 10 control frames, wait for the last one to be processed
        for _ in 0..<10 {
            let data = try encodeControlFrame(.ping)
            await transport.simulateIncoming(data)
        }

        // Wait for all 10 to be processed by reading them from the holder
        for _ in 0..<10 {
            _ = try await withTimeout(.seconds(2)) { await holder.next() }
        }

        #expect(await coordinator.diagnosticsSeenIDsCount == 0)

        await coordinator.stopAll()
    }
}
