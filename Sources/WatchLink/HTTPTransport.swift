import Foundation
import WatchLinkCore

public actor HTTPTransport: Transport {
    private let port: UInt16
    private nonisolated(unsafe) let urlSession: any URLSessionProtocol
    private var serverIP: String?
    private var incomingContinuation: AsyncStream<Data>.Continuation?
    private let reachabilityStream: AsyncStream<Bool>
    private let reachabilityContinuation: AsyncStream<Bool>.Continuation
    private var sseTask: Task<Void, Never>?
    private var _isReachable = false

    public var isReachable: Bool { _isReachable }

    public var reachabilityChanges: AsyncStream<Bool> {
        reachabilityStream
    }

    public init(port: UInt16, urlSession: any URLSessionProtocol = URLSession.shared) {
        self.port = port
        self.urlSession = urlSession

        let (stream, continuation) = AsyncStream<Bool>.makeStream()
        self.reachabilityStream = stream
        self.reachabilityContinuation = continuation
    }

    public func updateServerIP(_ ip: String) {
        serverIP = ip
        _isReachable = true
        reachabilityContinuation.yield(true)
    }

    public func clearServerIP() {
        serverIP = nil
        _isReachable = false
        reachabilityContinuation.yield(false)
        sseTask?.cancel()
    }

    public func start() async {}

    public func stop() async {
        sseTask?.cancel()
        sseTask = nil
        incomingContinuation?.finish()
        incomingContinuation = nil
        reachabilityContinuation.finish()
        _isReachable = false
    }

    public func send(_ data: Data) async throws {
        guard let url = url(for: .message) else {
            throw WatchLinkError.sendFailed("No server IP")
        }

        var request = URLRequest(url: url)
        request.httpMethod = HTTPRoute.message.method.rawValue
        request.httpBody = data
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

        let (_, response) = try await urlSession.data(for: request, delegate: nil)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw WatchLinkError.sendFailed("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }
    }

    public func incoming() -> AsyncStream<Data> {
        AsyncStream { continuation in
            incomingContinuation = continuation
            sseTask = Task { [weak self] in
                guard let self else { return }
                await self.listenSSE(continuation: continuation)
            }
        }
    }

    private func listenSSE(continuation: AsyncStream<Data>.Continuation) async {
        while !Task.isCancelled {
            guard let url = url(for: .events) else {
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = HTTPRoute.events.method.rawValue
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

            do {
                let (bytes, _) = try await urlSession.bytes(for: request, delegate: nil)
                for try await line in bytes.lines {
                    guard line.hasPrefix("data: ") else { continue }
                    let payload = Data(line.dropFirst(6).utf8)
                    continuation.yield(payload)
                }
            } catch {
                if Task.isCancelled { return }
            }
        }
    }

    private func url(for route: HTTPRoute) -> URL? {
        guard let ip = serverIP else { return nil }
        return URL(string: "http://\(ip):\(port)\(route.path)")
    }
}
