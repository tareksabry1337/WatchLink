import Foundation
import WatchLinkCore

package actor HTTPTransport: Transport {
    private let port: UInt16
    private let clock: AnyClock
    private let logger: WatchLinkLogger
    private nonisolated(unsafe) let urlSession: any URLSessionProtocol
    private var serverIP: String?
    private var incomingContinuation: AsyncStream<IncomingMessage>.Continuation?
    private var reachabilityContinuation: AsyncStream<Bool>.Continuation?
    private var sseTask: Task<Void, Never>?
    private var _isReachable = false

    package var isReachable: Bool { _isReachable }
    package var diagnosticsServerIP: String? { serverIP }

    package var reachabilityChanges: AsyncStream<Bool> {
        AsyncStream { continuation in
            reachabilityContinuation = continuation
        }
    }

    package init(port: UInt16, clock: AnyClock = AnyClock(), logger: WatchLinkLogger = .osLog, urlSession: any URLSessionProtocol = URLSession.shared) {
        self.port = port
        self.clock = clock
        self.logger = logger
        self.urlSession = urlSession
    }

    package func updateServerIP(_ ip: String) {
        logger.info("HTTP: server IP set to \(ip)")
        serverIP = ip
        _isReachable = true
        reachabilityContinuation?.yield(true)
        resetSSEConnection()
    }

    package func resetSSEConnection() {
        guard let continuation = incomingContinuation else { return }
        logger.info("HTTP: resetting SSE connection")
        sseTask?.cancel()
        sseTask = Task { [weak self] in
            guard let self else { return }
            await self.listenSSE(continuation: continuation)
        }
    }

    package func clearServerIP() {
        logger.info("HTTP: server IP cleared")
        serverIP = nil
        _isReachable = false
        reachabilityContinuation?.yield(false)
        sseTask?.cancel()
    }

    package func start() async {}

    package func stop() async {
        sseTask?.cancel()
        sseTask = nil
        incomingContinuation?.finish()
        incomingContinuation = nil
        reachabilityContinuation?.finish()
        reachabilityContinuation = nil
        _isReachable = false
    }

    package func send(_ data: Data) async throws {
        guard let url = url(for: .message) else {
            throw WatchLinkError.sendFailed("No server IP")
        }

        logger.debug("HTTP: POST \(url) (\(data.count) bytes)")
        var request = URLRequest(url: url)
        request.httpMethod = HTTPRoute.message.method.rawValue
        request.httpBody = data
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

        let (_, response) = try await urlSession.performRequest(request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            logger.warning("HTTP: POST failed with \(code)")
            throw WatchLinkError.sendFailed("HTTP \(code)")
        }
        logger.debug("HTTP: POST succeeded")
    }

    package func populateDiagnostics(_ diagnostics: inout WatchLinkDiagnostics) {
        diagnostics.httpReachable = isReachable
        diagnostics.serverIP = serverIP
    }

    package func reply(to frameID: String, with data: Data) async {
        guard let url = url(for: .reply) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = HTTPRoute.reply.method.rawValue
        request.httpBody = data
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue(frameID, forHTTPHeaderField: "X-Frame-ID")

        do {
            let (_, response) = try await urlSession.performRequest(request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                logger.warning("HTTP: reply failed with \(http.statusCode)")
            }
        } catch {
            logger.warning("HTTP: reply failed: \(error)")
        }
    }

    package func request(_ data: Data) async throws -> Data {
        guard let url = url(for: .request) else {
            throw WatchLinkError.sendFailed("No server IP")
        }

        logger.debug("HTTP: POST /request (\(data.count) bytes)")
        var request = URLRequest(url: url)
        request.httpMethod = HTTPRoute.request.method.rawValue
        request.httpBody = data
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

        let (responseData, response) = try await urlSession.performRequest(request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            logger.warning("HTTP: request failed with \(code)")
            throw WatchLinkError.sendFailed("HTTP \(code)")
        }
        logger.debug("HTTP: query response received (\(responseData.count) bytes)")
        return responseData
    }

    package func incoming() -> AsyncStream<IncomingMessage> {
        AsyncStream { continuation in
            incomingContinuation = continuation
            sseTask = Task { [weak self] in
                guard let self else { return }
                await self.listenSSE(continuation: continuation)
            }
        }
    }

    private func listenSSE(continuation: AsyncStream<IncomingMessage>.Continuation) async {
        var attempt = 0

        while !Task.isCancelled {
            guard _isReachable, let url = url(for: .events) else {
                let delay = JitteredBackoff.delay(attempt: attempt, max: .seconds(30))
                logger.debug("SSE: not reachable, retrying in \(delay)")
                try? await clock.sleep(for: delay)
                attempt += 1
                continue
            }

            logger.info("SSE: connecting to \(url)")
            var request = URLRequest(url: url)
            request.httpMethod = HTTPRoute.events.method.rawValue
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

            logger.info("SSE: connected")
            attempt = 0
            for await line in urlSession.streamLines(request) {
                guard line.hasPrefix("data: ") else { continue }
                let payload = Data(line.dropFirst(6).utf8)
                logger.debug("SSE: received event (\(payload.count) bytes)")
                continuation.yield(IncomingMessage(data: payload))
            }
            logger.info("SSE: stream ended")

            if Task.isCancelled { return }
            let delay = JitteredBackoff.delay(attempt: attempt, max: .seconds(30))
            logger.debug("SSE: reconnecting in \(delay)")
            try? await clock.sleep(for: delay)
            attempt += 1
        }
    }

    private func url(for route: HTTPRoute) -> URL? {
        guard let ip = serverIP else { return nil }
        return URL(string: "http://\(ip):\(port)\(route.path)")
    }
}
