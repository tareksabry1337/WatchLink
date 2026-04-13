import Foundation
import WatchConnectivity
import WatchLinkCore
#if canImport(WatchKit)
import WatchKit
#endif

@WatchLinkActor
public final class WatchLink: Sendable {
    private let coordinator: TransportCoordinator
    private let connectionManager: ConnectionManager
    private let bleDiscovery: BLEDiscovery?
    private let httpTransport: HTTPTransport?
    private let config: WatchLinkConfiguration
    private let sessionBridge: WCSessionBridge?
    private var bleDiscoveryTask: Task<Void, Never>?

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

    public func connect() async {
        coordinator.onHeartbeat { [weak connectionManager] in
            Task {
                await connectionManager?.heartbeatReceived()
            }
        }

        coordinator.startAll()
        startBLEDiscovery()
        connectionManager.connect()
        await observeAppLifecycle()
    }

    public func disconnect() async {
        connectionManager.disconnect()
        bleDiscoveryTask?.cancel()
        bleDiscoveryTask = nil
        bleDiscovery?.stopScanning()
        await coordinator.stopAll()
    }

    public func send<M: WatchLinkMessage>(_ message: M) throws where M.Response == NoResponse {
        try coordinator.send(message)
    }

    public func send<M: WatchLinkMessage>(_ message: M, timeout: Duration = .seconds(30)) async throws -> M.Response {
        try await coordinator.send(message, timeout: timeout)
    }

    public func reply<M: WatchLinkMessage>(with message: M, to received: ReceivedMessage<some WatchLinkMessage>) async throws {
        try await coordinator.reply(with: message, to: received.frameID)
    }

    public func messages<M: WatchLinkMessage>(_ type: M.Type) -> AsyncStream<ReceivedMessage<M>> {
        coordinator.messages(type)
    }

    public var connectionState: AsyncStream<ConnectionState> {
        get { connectionManager.connectionState }
    }

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

    private func startBLEDiscovery() {
        guard let bleDiscovery, let httpTransport else { return }
        bleDiscoveryTask = Task {
            for await ip in bleDiscovery.startScanning() {
                httpTransport.updateServerIP(ip)
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
