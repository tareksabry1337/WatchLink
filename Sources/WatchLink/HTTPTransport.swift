import Foundation
import WatchLinkCore

package actor HTTPTransport: Transport {
    private let port: UInt16
    private let clock: AnyClock
    private let logger: WatchLinkLogger
    private nonisolated(unsafe) let urlSession: any URLSessionProtocol
    private var serverIP: String?
    private var incomingContinuation: AsyncStream<IncomingMessage>.Continuation?
    private let reachabilityStream: AsyncStream<Bool>
    private let reachabilityContinuation: AsyncStream<Bool>.Continuation
    private var sseTask: Task<Void, Never>?
    private var _isReachable = false

    package var isReachable: Bool { _isReachable }
    package var diagnosticsServerIP: String? { serverIP }

    package var reachabilityChanges: AsyncStream<Bool> {
        reachabilityStream
    }

    package init(port: UInt16, clock: AnyClock = AnyClock(ContinuousClock()), logger: WatchLinkLogger = .osLog, urlSession: any URLSessionProtocol = URLSession.shared) {
        self.port = port
        self.clock = clock
        self.logger = logger
        self.urlSession = urlSession

        let (stream, continuation) = AsyncStream<Bool>.makeStream()
        self.reachabilityStream = stream
        self.reachabilityContinuation = continuation
    }

    package func updateServerIP(_ ip: String) {
        logger.info("HTTP: server IP set to \(ip)")
        serverIP = ip
        _isReachable = true
        reachabilityContinuation.yield(true)
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
        reachabilityContinuation.yield(false)
        sseTask?.cancel()
    }

    package func start() async {}

    package func stop() async {
        sseTask?.cancel()
        sseTask = nil
        incomingContinuation?.finish()
        incomingContinuation = nil
        reachabilityContinuation.finish()
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

        let (_, response) = try await urlSession.data(for: request, delegate: nil)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            logger.warning("HTTP: POST failed with \(code)")
            throw WatchLinkError.sendFailed("HTTP \(code)")
        }
        logger.debug("HTTP: POST succeeded")
    }

    package func respondToQuery(frameID: String, data: Data) async {}

    package func query(_ data: Data) async throws -> Data {
        guard let url = url(for: .query) else {
            throw WatchLinkError.sendFailed("No server IP")
        }

        logger.debug("HTTP: POST /query (\(data.count) bytes)")
        var request = URLRequest(url: url)
        request.httpMethod = HTTPRoute.query.method.rawValue
        request.httpBody = data
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

        let (responseData, response) = try await urlSession.data(for: request, delegate: nil)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            logger.warning("HTTP: query failed with \(code)")
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
        var retryDelay: Duration = .seconds(1)
        let maxRetryDelay: Duration = .seconds(30)

        while !Task.isCancelled {
            guard _isReachable, let url = url(for: .events) else {
                logger.debug("SSE: not reachable, retrying in \(retryDelay)")
                try? await clock.sleep(for: retryDelay)
                retryDelay = min(retryDelay * 2, maxRetryDelay)
                continue
            }

            logger.info("SSE: connecting to \(url)")
            var request = URLRequest(url: url)
            request.httpMethod = HTTPRoute.events.method.rawValue
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

            do {
                let (bytes, _) = try await urlSession.bytes(for: request, delegate: nil)
                logger.info("SSE: connected")
                retryDelay = .seconds(1)
                for try await line in bytes.lines {
                    guard line.hasPrefix("data: ") else { continue }
                    let payload = Data(line.dropFirst(6).utf8)
                    logger.debug("SSE: received event (\(payload.count) bytes)")
                    continuation.yield(IncomingMessage(data: payload))
                }
                logger.info("SSE: stream ended")
            } catch {
                if Task.isCancelled { return }
                logger.warning("SSE: error \(error), retrying in \(retryDelay)")
                try? await clock.sleep(for: retryDelay)
                retryDelay = min(retryDelay * 2, maxRetryDelay)
            }
        }
    }

    private func url(for route: HTTPRoute) -> URL? {
        guard let ip = serverIP else { return nil }
        return URL(string: "http://\(ip):\(port)\(route.path)")
    }
}
