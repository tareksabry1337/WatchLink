import Testing
import Foundation
@testable import WatchLinkCore
import WatchLinkTestSupport

@Suite("Memory")
struct MemoryTests {

    @Test("message subscription is cleaned up when stream is dropped")
    func subscriptionCleanedUp() async throws {
        let transport = MockTransport()
        let coordinator = TransportCoordinator(transports: [transport])
        await coordinator.startAll()

        do {
            let stream = await coordinator.messages(PingMessage.self)
            let task = Task {
                for await _ in stream { break }
            }
            await transport.simulateIncoming(try encodeFrame(PingMessage(count: 1)))
            await task.value
        }

        let stream = await coordinator.messages(PingMessage.self)
        await transport.simulateIncoming(try encodeFrame(PingMessage(count: 2)))

        let result: PingMessage = try await withTimeout(.seconds(1)) {
            for await msg in stream { return msg.value }
            throw StreamEndedError()
        }

        #expect(result.count == 2)
        await coordinator.stopAll()
    }

    @Test("multiple subscribe/unsubscribe cycles don't leak")
    func subscriptionCyclesDontLeak() async throws {
        let transport = MockTransport()
        let coordinator = TransportCoordinator(transports: [transport])
        await coordinator.startAll()

        for i in 0..<100 {
            let stream = await coordinator.messages(PingMessage.self)
            let task = Task {
                for await _ in stream { break }
            }
            await transport.simulateIncoming(try encodeFrame(PingMessage(count: i)))
            await task.value
        }

        let stream = await coordinator.messages(PingMessage.self)
        await transport.simulateIncoming(try encodeFrame(PingMessage(count: 999)))

        let result: PingMessage = try await withTimeout(.seconds(1)) {
            for await msg in stream { return msg.value }
            throw StreamEndedError()
        }

        #expect(result.count == 999)
        await coordinator.stopAll()
    }

    @Test("dropping all message streams finishes gracefully")
    func droppingStreamsFinishes() async throws {
        let transport = MockTransport()
        let coordinator = TransportCoordinator(transports: [transport])
        await coordinator.startAll()

        for _ in 0..<10 {
            _ = await coordinator.messages(PingMessage.self)
        }

        let stream = await coordinator.messages(PingMessage.self)
        await transport.simulateIncoming(try encodeFrame(PingMessage(count: 42)))

        let result: PingMessage = try await withTimeout(.seconds(1)) {
            for await msg in stream { return msg.value }
            throw StreamEndedError()
        }

        #expect(result.count == 42)
        await coordinator.stopAll()
    }
}
