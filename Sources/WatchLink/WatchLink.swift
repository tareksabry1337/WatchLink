import Foundation
import WatchConnectivity
import WatchLinkCore
#if canImport(WatchKit)
import WatchKit
#endif

/// Watch-side entry point to the multi-transport link.
///
/// Create one instance, call `connect()`, then `send(_:)` and iterate `messages(_:)`.
/// All public methods are isolated to `@WatchLinkActor`.
@WatchLinkActor
public final class WatchLink: Sendable {
    private let coordinator: TransportCoordinator
    private let connectionManager: ConnectionManager
    private let bleDiscovery: BLEDiscovery?
    private let httpTransport: HTTPTransport?
    private let config: WatchLinkConfiguration
    private let sessionBridge: WCSessionBridge?
    private var bleDiscoveryTask: Task<Void, Never>?

    /// Builds a `WatchLink` with a configured transport stack.
    public nonisolated init(_ configure: (inout WatchLinkConfiguration) -> Void) {
        var config = WatchLinkConfiguration()
        configure(&config)
        self.config = config

        var transports: [any Transport] = []
        var http: HTTPTransport?
        var ble: BLEDiscovery?
        var bridge: WCSessionBridge?

        if config.transports.contains(.watchConnectivity) {
            let wcTransport = WCTransport(session: WCSession.default)
            bridge = WCSessionBridge(transport: wcTransport)
            transports.append(wcTransport)
        }

        if config.transports.contains(.http),
           let serviceUUID = config.bleServiceUUID,
           let ipCharUUID = config.bleIPCharacteristicUUID {
            let transport = HTTPTransport(port: config.httpPort, clock: config.clock, logger: config.logger)
            http = transport
            transports.append(transport)

            ble = BLEDiscovery(
                serviceUUID: serviceUUID,
                ipCharacteristicUUID: ipCharUUID
            )
        }

        self.sessionBridge = bridge
        self.httpTransport = http
        self.bleDiscovery = ble
        self.coordinator = TransportCoordinator(
            transports: transports,
            clock: config.clock,
            retryInterval: config.retryInterval,
            logger: config.logger
        )

        self.connectionManager = ConnectionManager(coordinator: coordinator, config: config)
    }

    /// Starts every configured transport, begins BLE scanning, and observes app lifecycle.
    public func connect() async {
        coordinator.onHeartbeat { [weak connectionManager] in
            connectionManager?.heartbeatReceived()
        }

        coordinator.startAll()
        if let httpTransport, let bleDiscovery {
            startBLEDiscovery(transport: httpTransport, discovery: bleDiscovery)
        }
        connectionManager.connect()
        await observeAppLifecycle()
    }

    /// Stops every transport, cancels BLE scanning, and tears down lifecycle observers.
    public func disconnect() async {
        connectionManager.disconnect()
        bleDiscoveryTask?.cancel()
        bleDiscoveryTask = nil
        bleDiscovery?.stopScanning()
        await coordinator.stopAll()
    }

    /// Sends a fire-and-forget message. Queued and retried until the peer acks.
    public func send<M: WatchLinkMessage>(_ message: M) throws where M.Response == NoResponse {
        try coordinator.send(message)
    }

    /// Sends a message and awaits the peer's reply, or throws `WatchLinkError.requestTimedOut`.
    public func send<M: WatchLinkMessage>(_ message: M, timeout: Duration = .seconds(30)) async throws -> M.Response {
        try await coordinator.send(message, timeout: timeout)
    }

    /// Sends `message` as the reply to a previously-received request.
    public func reply<M: WatchLinkMessage>(with message: M, to received: ReceivedMessage<some WatchLinkMessage>) async throws {
        try await coordinator.reply(with: message, to: received.frameID)
    }

    /// Async stream of messages of the given type arriving from the peer.
    public func messages<M: WatchLinkMessage>(_ type: M.Type) -> AsyncStream<ReceivedMessage<M>> {
        coordinator.messages(type)
    }

    /// Stream of connection-state transitions. Yields the current state to new subscribers.
    public var connectionState: AsyncStream<ConnectionState> {
        get { connectionManager.connectionState }
    }

    /// Snapshot of transport internals for debug UI and instrumentation.
    public func diagnostics() -> WatchLinkDiagnostics {
        var diagnostics = WatchLinkDiagnostics()
        diagnostics.pendingQueueCount = coordinator.diagnosticsPendingCount
        diagnostics.seenIDsCount = coordinator.diagnosticsSeenIDsCount
        diagnostics.unackedCount = coordinator.diagnosticsUnackedCount
        diagnostics.pendingConfirmationsCount = coordinator.diagnosticsPendingConfirmationsCount

        for transport in coordinator.transports {
            transport.populateDiagnostics(&diagnostics)
        }

        return diagnostics
    }

    private func startBLEDiscovery(transport: HTTPTransport, discovery: BLEDiscovery) {
        bleDiscoveryTask = Task {
            for await ip in discovery.startScanning() {
                transport.updateServerIP(ip)
            }
        }
    }

    @MainActor
    private func observeAppLifecycle() {
        #if canImport(WatchKit)
        NotificationCenter.default.addObserver(
            forName: WKApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task {
                await self.httpTransport?.resetSSEConnection()
            }
        }
        #endif
    }
}
