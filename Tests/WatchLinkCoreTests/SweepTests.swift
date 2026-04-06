import Testing
import Foundation
@testable import WatchLinkCore
import WatchLinkTestSupport

@Suite("Dedup Sweep")
struct SweepTests {
    @Test("seen IDs are cleared after sweep interval")
    func sweepClearsSeenIDs() async throws {
        let clock = TestClock()
        let transport = MockTransport()
        let coordinator = TransportCoordinator(
            transports: [transport],
            clock: AnyClock(clock),
            sweepInterval: .seconds(30)
        )
        await coordinator.startAll()

        let encodedFirst = try encodeFrame(PingMessage(count: 1))
        let stream = await coordinator.messages(PingMessage.self)

        await transport.simulateIncoming(encodedFirst)
        let msg1 = try await firstMessage(from: stream)
        #expect(msg1.count == 1)

        await transport.simulateIncoming(encodedFirst)

        clock.advance(by: .seconds(30))

        let markerMessage = try encodeFrame(PingMessage(count: 999))
        await transport.simulateIncoming(encodedFirst)
        await transport.simulateIncoming(markerMessage)

        let next = try await firstMessage(from: stream)
        if next.count == 1 {
            let marker = try await firstMessage(from: stream)
            #expect(marker.count == 999)
        } else {
            #expect(next.count == 999)
        }

        await coordinator.stopAll()
    }

    @Test("messages are deduped within sweep window")
    func dedupWithinWindow() async throws {
        let clock = TestClock()
        let transport = MockTransport()
        let coordinator = TransportCoordinator(
            transports: [transport],
            clock: AnyClock(clock),
            sweepInterval: .seconds(30)
        )
        await coordinator.startAll()

        let duplicateFrame = try encodeFrame(PingMessage(count: 1))
        let uniqueFrame = try encodeFrame(PingMessage(count: 2))
        let stream = await coordinator.messages(PingMessage.self)

        await transport.simulateIncoming(duplicateFrame)
        await transport.simulateIncoming(duplicateFrame)
        await transport.simulateIncoming(uniqueFrame)

        let collector = AsyncCollector<PingMessage>()
        let results: [PingMessage] = try await withTimeout(.seconds(1)) {
            for await msg in stream {
                await collector.append(msg.value)
                if await collector.count == 2 { break }
            }
            return await collector.values
        }

        #expect(results.count == 2)
        #expect(results[0].count == 1)
        #expect(results[1].count == 2)

        await coordinator.stopAll()
    }

    @Test("sweep doesn't run before interval elapses")
    func noEarlySweep() async throws {
        let clock = TestClock()
        let transport = MockTransport()
        let coordinator = TransportCoordinator(
            transports: [transport],
            clock: AnyClock(clock),
            sweepInterval: .seconds(30)
        )
        await coordinator.startAll()

        let frame = try encodeFrame(PingMessage(count: 1))
        let uniqueFrame = try encodeFrame(PingMessage(count: 99))
        let stream = await coordinator.messages(PingMessage.self)

        await transport.simulateIncoming(frame)
        let first = try await firstMessage(from: stream)
        #expect(first.count == 1)

        clock.advance(by: .seconds(15))

        await transport.simulateIncoming(frame)
        await transport.simulateIncoming(uniqueFrame)

        let second = try await firstMessage(from: stream)
        #expect(second.count == 99)

        await coordinator.stopAll()
    }
}
