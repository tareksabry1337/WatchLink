import Foundation
import WatchConnectivity
import WatchLinkCore
#if canImport(UIKit)
import UIKit
#endif

public final class WatchLinkHost: Sendable {
    private let coordinator: TransportCoordinator
    private let httpServer: HTTPServer?
    private let bleAdvertiser: BLEAdvertiser?
    private let config: WatchLinkConfiguration
    private let sessionBridge: WCHostSessionBridge?

    public init(_ configure: (inout WatchLinkConfiguration) -> Void) {
        var config = WatchLinkConfiguration()
        configure(&config)
        self.config = config

        var transports: [any Transport] = []
        var httpServer: HTTPServer?
        var bleAdvertiser: BLEAdvertiser?
        var bridge: WCHostSessionBridge?

        if config.transports.contains(.watchConnectivity) {
            let wcTransport = WCHostTransport(session: WCSession.default)
            bridge = WCHostSessionBridge(transport: wcTransport)
            transports.append(wcTransport)
        }

        if config.transports.contains(.http),
           let serviceUUID = config.bleServiceUUID,
           let ipCharUUID = config.bleIPCharacteristicUUID {
            let server = HTTPServer(
                port: config.httpPort,
                heartbeatInterval: config.sseHeartbeatInterval,
                clock: config.clock,
                logger: config.logger
            )
            httpServer = server
            transports.append(server)

            bleAdvertiser = BLEAdvertiser(
                serviceUUID: serviceUUID,
                ipCharacteristicUUID: ipCharUUID
            )
        }

        self.sessionBridge = bridge
        self.httpServer = httpServer
        self.bleAdvertiser = bleAdvertiser
        self.coordinator = TransportCoordinator(
            transports: transports,
            clock: config.clock,
            sweepInterval: config.sweepInterval,
            retryInterval: config.retryInterval,
            logger: config.logger
        )
    }

    public func start() async throws {
        await coordinator.onControl { [weak self] frame in
            guard let self else { return }
            Task { await self.handleControl(frame) }
        }

        await coordinator.startAll()
        await startBLEAdvertising()
        observeAppLifecycle()
    }

    public func stop() async {
        await coordinator.stopAll()
        await bleAdvertiser?.stopAdvertising()
    }

    public func send<M: WatchLinkMessage>(_ message: M) async throws {
        try await coordinator.send(message)
    }

    public func send<M: WatchLinkMessage>(_ message: M, replyingTo received: ReceivedMessage<some WatchLinkMessage>) async throws {
        try await coordinator.send(message, replyingTo: received.frameID)
    }

    public func query<Q: WatchLinkQuery>(_ query: Q, timeout: Duration = .seconds(30)) async throws -> Q.Response {
        try await coordinator.query(query, timeout: timeout)
    }

    public func messages<M: WatchLinkMessage>(_ type: M.Type) async -> AsyncStream<ReceivedMessage<M>> {
        await coordinator.messages(type)
    }

    public func diagnostics() async -> WatchLinkDiagnostics {
        var d = WatchLinkDiagnostics()
        d.pendingQueueCount = await coordinator.diagnosticsPendingCount
        d.seenIDsCount = await coordinator.diagnosticsSeenIDsCount
        d.unackedCount = await coordinator.diagnosticsUnackedCount

        for transport in await coordinator.transports {
            if transport is WCHostTransport {
                d.wcReachable = await transport.isReachable
            }
            if let server = transport as? HTTPServer {
                d.sseClientCount = await server.diagnosticsSSEClientCount
                d.httpReachable = d.sseClientCount > 0
            }
        }

        return d
    }

    private func observeAppLifecycle() {
        #if canImport(UIKit)
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            Task { await self.handleBackground() }
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            Task { await self.handleForeground() }
        }
        #endif
    }

    private func handleBackground() async {
        await httpServer?.pause()
        await bleAdvertiser?.stopAdvertising()
    }

    private func handleForeground() async {
        await httpServer?.start()
        await startBLEAdvertising()
    }

    private func startBLEAdvertising() async {
        guard let server = httpServer, let ble = bleAdvertiser else { return }
        guard let ip = await server.localIP() else { return }
        await ble.startAdvertising(ip: ip)
    }

    private func handleControl(_ frame: ControlFrame) async {
        switch frame {
        case .ping:
            do {
                try await coordinator.sendControl(.pong)
            } catch {
                config.logger.error("Failed to send pong: \(error)")
            }
        case .pong:
            break
        case .ack:
            break
        }
    }
}
