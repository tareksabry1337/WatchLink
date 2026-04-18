#if os(iOS)
import Foundation
import WatchConnectivity
import WatchLinkCore
#if canImport(UIKit)
import UIKit
#endif

/// Phone-side entry point to the multi-transport link.
///
/// Create one instance, call `start()`, then iterate `messages(_:)` and reply or send.
/// All public methods are isolated to `@WatchLinkActor`.
@WatchLinkActor
public final class WatchLinkHost: Sendable {
    private let coordinator: TransportCoordinator
    private let httpServer: HTTPServer?
    private let bleAdvertiser: BLEAdvertiser?
    private let config: WatchLinkConfiguration
    private let sessionBridge: WCHostSessionBridge?

    /// Builds a `WatchLinkHost` with a configured transport stack.
    public nonisolated init(_ configure: (inout WatchLinkConfiguration) -> Void) {
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
            retryInterval: config.retryInterval,
            logger: config.logger
        )
    }

    /// Starts the HTTP server, begins BLE advertising, and observes app lifecycle.
    ///
    /// Throws `WatchLinkError.serverStartFailed` if the HTTP listener cannot bind.
    public func start() async throws {
        coordinator.onControl { [weak self] frame in
            guard let self else { return }
            Task {
                await self.handleControl(frame)
            }
        }

        coordinator.startAll()
        await startBLEAdvertising()
        await observeAppLifecycle()
    }

    /// Stops every transport and tears down BLE advertising.
    public func stop() async {
        await coordinator.stopAll()
        bleAdvertiser?.stopAdvertising()
    }

    /// Sends a fire-and-forget message to the watch. Queued and retried until acked.
    public func send<M: WatchLinkMessage>(_ message: M) throws where M.Response == NoResponse {
        try coordinator.send(message)
    }

    /// Sends a message and awaits the watch's reply, or throws `WatchLinkError.requestTimedOut`.
    public func send<M: WatchLinkMessage>(_ message: M, timeout: Duration = .seconds(30)) async throws -> M.Response {
        try await coordinator.send(message, timeout: timeout)
    }

    /// Sends `message` as the reply to a previously-received request from the watch.
    public func reply<M: WatchLinkMessage>(with message: M, to received: ReceivedMessage<some WatchLinkMessage>) async throws {
        try await coordinator.reply(with: message, to: received.frameID)
    }

    /// Async stream of messages of the given type arriving from the watch.
    public func messages<M: WatchLinkMessage>(_ type: M.Type) -> AsyncStream<ReceivedMessage<M>> {
        coordinator.messages(type)
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

    @MainActor private func observeAppLifecycle() {
        #if canImport(UIKit)
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task {
                await self.handleBackground()
            }
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task {
                await self.handleForeground()
            }
        }
        #endif
    }

    private func handleBackground() {
        httpServer?.pause()
        bleAdvertiser?.stopAdvertising()
    }

    private func handleForeground() async {
        httpServer?.start()
        await startBLEAdvertising()
    }

    private func startBLEAdvertising() async {
        guard let server = httpServer, let ble = bleAdvertiser else { return }
        guard let ip = await server.localIP() else { return }
        ble.startAdvertising(ip: ip)
    }

    private func handleControl(_ frame: ControlFrame) {
        switch frame {
        case .ping:
            do {
                try coordinator.sendControl(.pong)
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
#endif
