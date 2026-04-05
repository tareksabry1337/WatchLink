import Foundation
import WatchConnectivity
import WatchLinkCore

public final class WatchLink: Sendable {
    private let coordinator: TransportCoordinator
    private let connectionManager: ConnectionManager
    private let bleDiscovery: BLEDiscovery?
    private let httpTransport: HTTPTransport?
    private let config: WatchLinkConfiguration
    private let sessionBridge: WCSessionBridge?

    public init(_ configure: (inout WatchLinkConfiguration) -> Void) {
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
            let transport = HTTPTransport(port: config.httpPort)
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
            sweepInterval: config.sweepInterval,
            logger: config.logger
        )
        
        self.connectionManager = ConnectionManager(coordinator: coordinator, config: config)
    }

    public func connect() async {
        await coordinator.startAll()

        if let ble = bleDiscovery, let http = httpTransport {
            Task {
                for await ip in await ble.startScanning() {
                    await http.updateServerIP(ip)
                }
            }
        }

        await connectionManager.connect()
    }

    public func disconnect() async {
        await connectionManager.disconnect()
        await bleDiscovery?.stopScanning()
        await coordinator.stopAll()
    }

    public func send<M: WatchLinkMessage>(_ message: M) async throws {
        try await coordinator.send(message)
    }

    public func reply<R: WatchLinkMessage>(to received: ReceivedMessage<some WatchLinkMessage>, with message: R) async throws {
        try await coordinator.reply(toFrameID: received.frameID, with: message)
    }

    public func messages<M: WatchLinkMessage>(_ type: M.Type) async -> AsyncStream<ReceivedMessage<M>> {
        await coordinator.messages(type)
    }

    public var connectionState: AsyncStream<ConnectionState> {
        get async { await connectionManager.connectionState }
    }
}
