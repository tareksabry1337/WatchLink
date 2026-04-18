import Testing
import Foundation
@testable import WatchLinkCore
@testable import WatchLink
import WatchLinkTestSupport

@Suite("ConnectionManager")
struct ConnectionManagerTests {

    private func makeManager(
        transport: MockTransport = MockTransport()
    ) -> (ConnectionManager, MockTransport, TransportCoordinator) {
        var config = WatchLinkConfiguration()
        config.pingInterval = .seconds(60)
        let coordinator = TransportCoordinator(transports: [transport])
        let manager = ConnectionManager(coordinator: coordinator, config: config)
        return (manager, transport, coordinator)
    }

    // MARK: - State Transitions

    @Test("initial state is disconnected")
    func initialState() async throws {
        let (manager, _, _) = makeManager()
        let stream = await manager.connectionState

        let state: ConnectionState = try await withTimeout(.seconds(10)) {
            for await s in stream { return s }
            throw StreamEndedError()
        }

        #expect(state == .disconnected)
    }

    @Test("connect transitions through connecting → connected on heartbeat")
    func connectTransitions() async throws {
        let (manager, _, coordinator) = makeManager()
        await coordinator.startAll()

        let collector = AsyncCollector<ConnectionState>()
        let stream = await manager.connectionState

        let collectTask = Task {
            for await state in stream {
                await collector.append(state)
                if state == .connected { break }
            }
        }

        await manager.connect()
        await manager.heartbeatReceived()
        try await withTimeout(.seconds(10)) { await collectTask.value }

        let states = await collector.values
        #expect(states.contains(.disconnected))
        #expect(states.contains(.connecting))
        #expect(states.contains(.connected))

        await manager.disconnect()
        await coordinator.stopAll()
    }

    @Test("disconnect transitions to disconnected")
    func disconnectTransition() async throws {
        let (manager, _, coordinator) = makeManager()
        await coordinator.startAll()

        await manager.connect()
        await manager.heartbeatReceived()

        let collector = AsyncCollector<ConnectionState>()
        let stream = await manager.connectionState

        let collectTask = Task {
            for await state in stream {
                await collector.append(state)
                let count = await collector.values.count
                if state == .disconnected && count > 1 { break }
            }
        }

        await manager.disconnect()
        try await withTimeout(.seconds(10)) { await collectTask.value }

        let states = await collector.values
        #expect(states.last == .disconnected)

        await coordinator.stopAll()
    }

    @Test("connect with unreachable transport queues ping and transitions to connected")
    func connectQueuesWhenUnreachable() async throws {
        let transport = MockTransport()
        await transport.setUnreachable()
        let (manager, _, coordinator) = makeManager(transport: transport)
        await coordinator.startAll()

        let collector = AsyncCollector<ConnectionState>()
        let stream = await manager.connectionState

        let collectTask = Task {
            for await state in stream {
                await collector.append(state)
                if state == .connected { break }
            }
        }

        await manager.connect()
        await manager.heartbeatReceived()
        try await withTimeout(.seconds(10)) { await collectTask.value }

        let states = await collector.values
        #expect(states.contains(.connected))

        await manager.disconnect()
        await coordinator.stopAll()
    }

    // MARK: - Multiple Subscribers

    @Test("multiple subscribers each receive state updates")
    func multipleSubscribers() async throws {
        let (manager, _, coordinator) = makeManager()
        await coordinator.startAll()

        let stream1 = await manager.connectionState
        let stream2 = await manager.connectionState

        let collector1 = AsyncCollector<ConnectionState>()
        let collector2 = AsyncCollector<ConnectionState>()

        let t1 = Task {
            for await state in stream1 {
                await collector1.append(state)
                if state == .connected { break }
            }
        }
        let t2 = Task {
            for await state in stream2 {
                await collector2.append(state)
                if state == .connected { break }
            }
        }

        await manager.connect()
        await manager.heartbeatReceived()
        try await withTimeout(.seconds(10)) {
            await t1.value
            await t2.value
        }

        let states1 = await collector1.values
        let states2 = await collector2.values
        #expect(states1.contains(.connected))
        #expect(states2.contains(.connected))

        await manager.disconnect()
        await coordinator.stopAll()
    }

    @Test("dropped subscriber doesn't affect others")
    func droppedSubscriber() async throws {
        let (manager, _, coordinator) = makeManager()
        await coordinator.startAll()

        let stream1 = await manager.connectionState
        let stream2 = await manager.connectionState

        // Start and immediately break stream1
        let t1 = Task {
            for await _ in stream1 { break }
        }
        try await withTimeout(.seconds(10)) { await t1.value }

        // stream2 should still work
        let collector = AsyncCollector<ConnectionState>()
        let t2 = Task {
            for await state in stream2 {
                await collector.append(state)
                if state == .connected { break }
            }
        }

        await manager.connect()
        await manager.heartbeatReceived()
        try await withTimeout(.seconds(10)) { await t2.value }

        let states = await collector.values
        #expect(states.contains(.connected))

        await manager.disconnect()
        await coordinator.stopAll()
    }

    // MARK: - No-op State

    @Test("duplicate state doesn't emit to subscribers")
    func noOpStateUpdate() async throws {
        let (manager, _, coordinator) = makeManager()
        await coordinator.startAll()

        let collector = AsyncCollector<ConnectionState>()
        let stream = await manager.connectionState

        let collectTask = Task {
            for await state in stream {
                await collector.append(state)
                if state == .connected { break }
            }
        }

        await manager.connect()
        await manager.heartbeatReceived()
        try await withTimeout(.seconds(10)) { await collectTask.value }

        let states = await collector.values
        let connectedCount = states.filter { $0 == .connected }.count
        #expect(connectedCount == 1)

        await manager.disconnect()
        await coordinator.stopAll()
    }

    // MARK: - Connect / Disconnect / Reconnect cycle

    @Test("can reconnect after disconnect")
    func reconnectAfterDisconnect() async throws {
        let (manager, _, coordinator) = makeManager()
        await coordinator.startAll()

        await manager.connect()
        await manager.heartbeatReceived()
        await manager.disconnect()

        let collector = AsyncCollector<ConnectionState>()
        let stream = await manager.connectionState

        let collectTask = Task {
            for await state in stream {
                await collector.append(state)
                if state == .connected { break }
            }
        }

        await manager.connect()
        await manager.heartbeatReceived()
        try await withTimeout(.seconds(10)) { await collectTask.value }

        let states = await collector.values
        #expect(states.contains(.connected))

        await manager.disconnect()
        await coordinator.stopAll()
    }
}

