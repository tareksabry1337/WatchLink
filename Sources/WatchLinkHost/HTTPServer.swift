import Foundation
import Network
import WatchLinkCore

package actor HTTPServer: Transport {
    private let port: UInt16
    private let heartbeatInterval: Duration
    private let clock: AnyClock
    private var listener: NWListener?
    private var incomingContinuation: AsyncStream<IncomingMessage>.Continuation?
    private var reachabilityContinuation: AsyncStream<Bool>.Continuation?
    private var sseClients: [UUID: NWConnection] = [:]
    private var heartbeatTask: Task<Void, Never>?
    private var _isReachable = false

    package var isReachable: Bool { _isReachable }

    package var reachabilityChanges: AsyncStream<Bool> {
        AsyncStream { continuation in
            reachabilityContinuation = continuation
        }
    }

    package func localIP() async -> String? {
        await NetworkUtils.localIPAddress()
    }

    package init(port: UInt16, heartbeatInterval: Duration = .seconds(15), clock: AnyClock = AnyClock(ContinuousClock())) {
        self.port = port
        self.heartbeatInterval = heartbeatInterval
        self.clock = clock
    }

    package func start() async {
        do {
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                throw WatchLinkError.serverStartFailed("Invalid port: \(port)")
            }
            let newListener = try NWListener(using: .tcp, on: nwPort)

            newListener.newConnectionHandler = { [weak self] connection in
                guard let self else { return }
                Task { await self.handleConnection(connection) }
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

    package func pause() async {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        listener?.cancel()
        listener = nil
        _isReachable = false
        for (_, connection) in sseClients {
            connection.cancel()
        }
        sseClients.removeAll()
    }

    package func stop() async {
        await pause()
        incomingContinuation?.finish()
        reachabilityContinuation?.finish()
    }

    package func send(_ data: Data) async throws {
        pushSSEEvent(data)
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

            let contentLength = self.parseContentLength(raw)
            let bodyStart = raw.distance(from: raw.startIndex, to: separatorRange.upperBound)
            let bodyReceived = buffer.count - bodyStart

            if contentLength > 0 && bodyReceived < contentLength {
                self.receiveFullRequest(on: connection, accumulated: buffer)
                return
            }

            Task { await self.routeRequest(data: buffer, connection: connection) }
        }
    }

    private nonisolated func parseContentLength(_ raw: String) -> Int {
        for line in raw.components(separatedBy: "\r\n") {
            if line.lowercased().hasPrefix("content-length:") {
                let value = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
                return Int(value) ?? 0
            }
        }
        return 0
    }

    private func routeRequest(data: Data, connection: NWConnection) {
        let raw = String(data: data, encoding: .utf8) ?? ""
        let request = parseHTTPRequest(raw)

        switch request.route {
        case .message:
            if let body = request.body {
                incomingContinuation?.yield(IncomingMessage(data: body))
            }
            respond(status: .ok, on: connection)

        case .events:
            startSSEStream(on: connection)

        case .health:
            respond(status: .ok, on: connection)

        case nil:
            respond(status: .notFound, on: connection)
        }
    }

    private func startSSEStream(on connection: NWConnection) {
        let clientID = UUID()
        sseClients[clientID] = connection

        let header = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nConnection: keep-alive\r\n\r\n"
        connection.send(content: Data(header.utf8), completion: .contentProcessed { _ in })

        connection.stateUpdateHandler = { [weak self] state in
            if case .cancelled = state {
                Task { await self?.removeSSEClient(clientID) }
            }
        }
    }

    private func pushSSEEvent(_ data: Data) {
        guard let encoded = String(data: data, encoding: .utf8) else { return }
        let event = Data("data: \(encoded)\n\n".utf8)

        for (id, connection) in sseClients {
            connection.send(content: event, completion: .contentProcessed { [weak self] error in
                if error != nil {
                    Task { await self?.removeSSEClient(id) }
                }
            })
        }
    }

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                try? await self.clock.sleep(for: self.heartbeatInterval)
                guard !Task.isCancelled else { return }
                await self.sendHeartbeat()
            }
        }
    }

    private func sendHeartbeat() {
        let heartbeat = Data(":heartbeat\n\n".utf8)
        for (id, connection) in sseClients {
            connection.send(content: heartbeat, completion: .contentProcessed { [weak self] error in
                if error != nil {
                    Task { await self?.removeSSEClient(id) }
                }
            })
        }
    }

    private func removeSSEClient(_ id: UUID) {
        sseClients[id]?.cancel()
        sseClients[id] = nil
    }

    private struct ParsedRequest {
        let route: HTTPRoute?
        let body: Data?
    }

    private func parseHTTPRequest(_ raw: String) -> ParsedRequest {
        let lines = raw.components(separatedBy: "\r\n")
        let requestLine = lines.first?.components(separatedBy: " ") ?? []
        let method = HTTPMethod(rawValue: requestLine.count > 0 ? requestLine[0] : "")
        let path = requestLine.count > 1 ? requestLine[1] : ""
        let route = method.flatMap { HTTPRoute(method: $0, path: path) }

        var body: Data?
        if let separatorRange = raw.range(of: "\r\n\r\n") {
            let bodyString = String(raw[separatorRange.upperBound...])
            if !bodyString.isEmpty {
                body = Data(bodyString.utf8)
            }
        }

        return ParsedRequest(route: route, body: body)
    }

    private enum HTTPStatus: Int, Sendable {
        case ok = 200
        case notFound = 404

        var text: String {
            switch self {
            case .ok: "OK"
            case .notFound: "Not Found"
            }
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
