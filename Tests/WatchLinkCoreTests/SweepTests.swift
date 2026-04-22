import Testing
import Foundation
@testable import WatchLinkCore
import WatchLinkTestSupport

@Suite("Confirmation Cleanup")
struct ConfirmationCleanupTests {

    @Test("confirmation removes message ID from seenIDs without any timer")
    func confirmationRemovesSeenID() async throws {
        let transport = MockTransport()
        let coordinator = TransportCoordinator(transports: [transport])
        await coordinator.startAll()

        // Receive a message — adds to seenIDs
        let messageData = try encodeFrame(PingMessage(count: 1))
        let frame = try JSONDecoder().decode(Frame.self, from: messageData)
        let pingStream = await coordinator.messages(PingMessage.self)
        await transport.simulateIncoming(messageData)
        _ = try await firstMessage(from: pingStream)

        #expect(await coordinator.diagnosticsSeenIDsCount == 1)

        // Receive a frame carrying confirmation for that ID
        let confirmData = try encodeFrame(PongMessage(count: 1), confirmedAcks: [frame.id])
        let pongStream = await coordinator.messages(PongMessage.self)
        await transport.simulateIncoming(confirmData)
        _ = try await firstMessage(from: pongStream)

        // seenIDs has 1 entry (PongMessage's own ID) — original was removed by confirmation
        #expect(await coordinator.diagnosticsSeenIDsCount == 1)

        await coordinator.stopAll()
    }

    @Test("dedup holds until confirmation is received")
    func dedupHoldsWithoutConfirmation() async throws {
        let transport = MockTransport()
        let coordinator = TransportCoordinator(transports: [transport])
        await coordinator.startAll()

        let encoder = JSONEncoder()
        let duplicateFrame = try Frame(wrapping: PingMessage(count: 1), encoder: encoder, confirmedAcks: [])
        let duplicateData = try encoder.encode(duplicateFrame)
        let uniqueData = try encodeFrame(PingMessage(count: 2))

        let results = try await withTimeout(.seconds(30)) {
            let stream = await coordinator.messages(PingMessage.self)
            await transport.simulateIncoming(duplicateData)
            await transport.simulateIncoming(duplicateData) // duplicate — should be dropped
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

    @Test("seenIDs does not grow from control frame traffic")
    func seenIDsStableWithControlTraffic() async throws {
        let transport = MockTransport()
        let coordinator = TransportCoordinator(transports: [transport])
        let holder = AsyncHolder<ControlFrame>()

        await coordinator.onControl { frame in
            Task { await holder.send(frame) }
        }
        await coordinator.startAll()

        // Send many pings — none should accumulate in seenIDs
        for _ in 0..<20 {
            let data = try encodeControlFrame(.ping)
            await transport.simulateIncoming(data)
        }

        // Wait for all 20 to be processed
        for _ in 0..<20 {
            _ = try await withTimeout(.seconds(30)) { await holder.next() }
        }

        #expect(await coordinator.diagnosticsSeenIDsCount == 0)

        await coordinator.stopAll()
    }
}
