#if os(iOS)
import Foundation
import Network
import WatchLinkCore

private struct SSEClient {
    let connection: NWConnection
    var lastActivity: Instant
}

@WatchLinkActor
package final class HTTPServer: Transport {
    private let port: UInt16
    private let heartbeatInterval: Duration
    private let clock: AnyClock
    private let logger: WatchLinkLogger
    private var listener: NWListener?
    private var incomingContinuation: AsyncStream<IncomingMessage>.Continuation?
    private var reachabilityContinuation: AsyncStream<Bool>.Continuation?
    private var sseClients: [UUID: SSEClient] = [:]
    private var pendingReplyConnections: [String: NWConnection] = [:]
    private var pendingRequestContinuations: [String: CheckedContinuation<Data, Error>] = [:]
    private var heartbeatTask: Task<Void, Never>?
    private var _isReachable = false

    package var isReachable: Bool { _isReachable && !sseClients.isEmpty }

    package var boundPort: UInt16? { listener?.port?.rawValue }

    package var reachabilityChanges: AsyncStream<Bool> {
        AsyncStream { continuation in
            reachabilityContinuation = continuation
        }
    }

    package func localIP() async -> String? {
        await NetworkUtils.localIPAddress()
    }

    package var diagnosticsSSEClientCount: Int { sseClients.count }

    package func populateDiagnostics(_ diagnostics: inout WatchLinkDiagnostics) {
        diagnostics.sseClientCount = sseClients.count
        diagnostics.httpReachable = sseClients.count > 0
    }

    package nonisolated init(
        port: UInt16,
        heartbeatInterval: Duration = .seconds(15),
        clock: AnyClock = AnyClock(),
        logger: WatchLinkLogger = .osLog
    ) {
        self.port = port
        self.heartbeatInterval = heartbeatInterval
        self.clock = clock
        self.logger = logger

    }

    package func start() {
        do {
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                throw WatchLinkError.serverStartFailed("Invalid port: \(port)")
            }
            let newListener = try NWListener(using: .tcp, on: nwPort)

            newListener.newConnectionHandler = { [weak self] connection in
                guard let self else { return }
                Task {
                    await self.handleConnection(connection)
                }
            }

            newListener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                Task {
                    switch state {
                    case .ready:
                        await self.setReachable(true)
                    case .failed, .cancelled:
                        await self.setReachable(false)
                    default:
                        break
                    }
                }
            }

            newListener.start(queue: .global(qos: .userInitiated))
            listener = newListener
            startHeartbeat()
        } catch {
            _isReachable = false
        }
    }

    package func pause() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        listener?.cancel()
        listener = nil
        _isReachable = false
        for (_, client) in sseClients {
            client.connection.cancel()
        }
        sseClients.removeAll()
        for (_, connection) in pendingReplyConnections {
            connection.cancel()
        }
        pendingReplyConnections.removeAll()
        for (_, continuation) in pendingRequestContinuations {
            continuation.resume(throwing: WatchLinkError.sendFailed("Server stopped"))
        }
        pendingRequestContinuations.removeAll()
    }

    package func stop() {
        pause()
        incomingContinuation?.finish()
        incomingContinuation = nil
        reachabilityContinuation?.finish()
        reachabilityContinuation = nil
    }

    package func send(_ data: Data) async throws {
        pushSSEEvent(data)
    }

    package func request(_ data: Data) async throws -> Data {
        guard let frame = try? JSONDecoder().decode(Frame.self, from: data) else {
            throw WatchLinkError.sendFailed("Failed to decode frame for request")
        }

        let frameID = frame.id
        logger.debug("HTTP server: request \(frameID), pushing via SSE and awaiting reply")

        return try await withCheckedThrowingContinuation { continuation in
            pendingRequestContinuations[frameID] = continuation
            pushSSEEvent(data)
        }
    }

    package func incoming() -> AsyncStream<IncomingMessage> {
        AsyncStream { continuation in
            incomingContinuation = continuation
        }
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        receiveFullRequest(on: connection, accumulated: Data())
    }

    private nonisolated func receiveFullRequest(on connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self, let data, error == nil else {
                connection.cancel()
                return
            }

            var buffer = accumulated
            buffer.append(data)

            let raw = String(data: buffer, encoding: .utf8) ?? ""

            guard let separatorRange = raw.range(of: "\r\n\r\n") else {
                self.receiveFullRequest(on: connection, accumulated: buffer)
                return
            }

            let contentLength = HTTPRequestRouter.parseContentLength(raw)
            let bodyStart = raw.distance(from: raw.startIndex, to: separatorRange.upperBound)
            let bodyReceived = buffer.count - bodyStart

            if contentLength > 0 && bodyReceived < contentLength {
                self.receiveFullRequest(on: connection, accumulated: buffer)
                return
            }

            Task {
                await self.routeRequest(data: buffer, connection: connection)
            }
        }
    }

    private func routeRequest(data: Data, connection: NWConnection) {
        let parsed = HTTPRequestRouter.parse(data)
        logger.debug("HTTP server: \(parsed.route?.path ?? "unknown") (\(parsed.body?.count ?? 0) bytes)")

        for effect in HTTPRequestRouter.effects(for: parsed) {
            apply(effect, on: connection)
        }
    }

    private func apply(_ effect: HTTPEffect, on connection: NWConnection) {
        switch effect {
        case .yieldIncoming(let data):
            incomingContinuation?.yield(IncomingMessage(data: data))

        case .holdConnection(let frameID):
            pendingReplyConnections[frameID] = connection
            logger.debug("HTTP server: holding connection for reply \(frameID)")

        case .resolveReply(let frameID, let body):
            if let continuation = pendingRequestContinuations.removeValue(forKey: frameID) {
                continuation.resume(returning: body)
            }

        case .startSSE:
            logger.info("HTTP server: SSE client connecting")
            startSSEStream(on: connection)

        case .respond(let status, let body):
            respond(status: status, body: body, on: connection)
        }
    }

    package func reply(to frameID: String, with data: Data) {
        guard let connection = pendingReplyConnections.removeValue(forKey: frameID) else {
            logger.debug("HTTP server: no pending connection for \(frameID)")
            return
        }

        logger.debug("HTTP server: replying to \(frameID) (\(data.count) bytes)")
        respond(status: .ok, body: data, on: connection)
    }

    private func startSSEStream(on connection: NWConnection) {
        let clientID = UUID()
        sseClients[clientID] = SSEClient(connection: connection, lastActivity: .now)
        logger.info("HTTP server: SSE client connected (total: \(self.sseClients.count))")

        reachabilityContinuation?.yield(true)

        let header = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nConnection: keep-alive\r\n\r\n"
        connection.send(content: Data(header.utf8), completion: .contentProcessed { _ in })

        connection.stateUpdateHandler = { [weak self] state in
            if case .cancelled = state {
                Task {
                    await self?.removeSSEClient(clientID)
                }
            }
        }
    }

    private func pushSSEEvent(_ data: Data) {
        guard let encoded = String(data: data, encoding: .utf8) else { return }
        let event = Data("data: \(encoded)\n\n".utf8)
        logger.debug("SSE: pushing to \(self.sseClients.count) client(s) (\(data.count) bytes)")

        for (id, client) in sseClients {
            client.connection.send(content: event, completion: .contentProcessed { [weak self] error in
                if error != nil {
                    Task {
                        await self?.removeSSEClient(id)
                    }
                } else {
                    Task {
                        await self?.markClientActive(id)
                    }
                }
            })
        }
    }

    private func markClientActive(_ id: UUID) {
        sseClients[id]?.lastActivity = .now
    }

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                try? await clock.sleep(for: self.heartbeatInterval)
                guard !Task.isCancelled else { return }
                sendHeartbeat()
            }
        }
    }

    private func sendHeartbeat() {
        let staleThreshold = heartbeatInterval * 3
        let now = Instant.now

        for (id, client) in sseClients {
            if now - client.lastActivity > staleThreshold {
                logger.info("SSE: removing stale client (no activity for \(now - client.lastActivity))")
                removeSSEClient(id)
                continue
            }

            client.connection.send(content: Data(":heartbeat\n\n".utf8), completion: .contentProcessed { [weak self] error in
                if error != nil {
                    Task {
                        await self?.removeSSEClient(id)
                    }
                } else {
                    Task {
                        await self?.markClientActive(id)
                    }
                }
            })
        }
    }

    private func removeSSEClient(_ id: UUID) {
        sseClients[id]?.connection.cancel()
        sseClients[id] = nil
        logger.info("SSE: client removed (remaining: \(self.sseClients.count))")

        if sseClients.isEmpty {
            reachabilityContinuation?.yield(false)
        }
    }

    private func respond(status: HTTPStatus, body: Data? = nil, on connection: NWConnection) {
        var header = "HTTP/1.1 \(status.rawValue) \(status.text)\r\n"
        header += "Content-Length: \(body?.count ?? 0)\r\n"
        header += "\r\n"

        var payload = Data(header.utf8)
        if let body { payload.append(body) }

        connection.send(content: payload, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func setReachable(_ value: Bool) {
        _isReachable = value
        reachabilityContinuation?.yield(value)
    }
}
#endif
