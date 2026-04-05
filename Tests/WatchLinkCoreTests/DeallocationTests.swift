import Testing
import Foundation
@testable import WatchLinkCore
import WatchLinkTestSupport

@Suite("Deallocation")
struct DeallocationTests {

    @Test("coordinator is deallocated after stopAll")
    func coordinatorDeallocated() async {
        let transport = MockTransport()
        var coordinator: TransportCoordinator? = TransportCoordinator(transports: [transport])
        weak var weakRef = coordinator

        await coordinator?.startAll()
        await coordinator?.stopAll()
        coordinator = nil

        #expect(weakRef == nil)
    }

    @Test("coordinator with control handler is deallocated after stopAll")
    func coordinatorWithControlHandler() async {
        let transport = MockTransport()
        var coordinator: TransportCoordinator? = TransportCoordinator(transports: [transport])
        weak var weakRef = coordinator

        await coordinator?.onControl { _ in }
        await coordinator?.startAll()
        await coordinator?.stopAll()
        coordinator = nil

        #expect(weakRef == nil)
    }

    @Test("coordinator with active subscription is deallocated after stopAll")
    func coordinatorWithSubscription() async {
        let transport = MockTransport()
        var coordinator: TransportCoordinator? = TransportCoordinator(transports: [transport])
        weak var weakRef = coordinator

        await coordinator?.startAll()
        let stream = await coordinator?.messages(PingMessage.self)
        _ = stream
        await coordinator?.stopAll()
        coordinator = nil

        #expect(weakRef == nil)
    }

    @Test("coordinator with sweep task is deallocated after stopAll")
    func coordinatorWithSweep() async {
        let clock = TestClock()
        let transport = MockTransport()
        var coordinator: TransportCoordinator? = TransportCoordinator(
            transports: [transport],
            clock: AnyClock(clock),
            sweepInterval: .seconds(10)
        )
        weak var weakRef = coordinator

        await coordinator?.startAll()
        await coordinator?.stopAll()
        coordinator = nil

        #expect(weakRef == nil)
    }

    @Test("transport is not retained by coordinator after stopAll and release")
    func transportNotRetained() async {
        var transport: MockTransport? = MockTransport()
        weak var weakTransport = transport

        var coordinator: TransportCoordinator? = TransportCoordinator(transports: [transport!])
        await coordinator?.startAll()
        await coordinator?.stopAll()
        coordinator = nil
        transport = nil

        #expect(weakTransport == nil)
    }

    @Test("multiple start/stop cycles don't leak")
    func multipleStartStop() async {
        let transport = MockTransport()
        var coordinator: TransportCoordinator? = TransportCoordinator(transports: [transport])
        weak var weakRef = coordinator

        for _ in 0..<5 {
            await coordinator?.startAll()
            await coordinator?.stopAll()
        }
        coordinator = nil

        #expect(weakRef == nil)
    }

    @Test("coordinator with messages sent is deallocated after stopAll")
    func coordinatorAfterMessages() async throws {
        let transport = MockTransport()
        var coordinator: TransportCoordinator? = TransportCoordinator(transports: [transport])
        weak var weakRef = coordinator

        await coordinator?.startAll()
        try await coordinator?.send(PingMessage(count: 1))
        try await coordinator?.send(PingMessage(count: 2))
        await coordinator?.stopAll()
        coordinator = nil

        #expect(weakRef == nil)
    }
}
