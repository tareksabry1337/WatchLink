import Foundation

package protocol URLSessionProtocol: Sendable {
    func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse)
    func streamLines(_ request: URLRequest) -> AsyncStream<String>
}

extension URLSession: URLSessionProtocol {
    package func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        if #available(iOS 15.0, watchOS 8.0, *) {
            return try await data(for: request)
        } else {
            return try await performRequestUsingDataTask(request)
        }
    }

    package func performRequestUsingDataTask(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let data, let response else {
                    continuation.resume(throwing: WatchLinkError.sendFailed("No response"))
                    return
                }
                continuation.resume(returning: (data, response))
            }.resume()
        }
    }

    package func streamLines(_ request: URLRequest) -> AsyncStream<String> {
        if #available(iOS 15.0, watchOS 8.0, *) {
            return streamLinesUsingAsyncBytes(request)
        } else {
            return streamLinesUsingDelegate(request)
        }
    }

    @available(iOS 15.0, watchOS 8.0, *)
    package func streamLinesUsingAsyncBytes(_ request: URLRequest) -> AsyncStream<String> {
        AsyncStream { continuation in
            let task = Task {
                do {
                    let (bytes, _) = try await self.bytes(for: request)
                    for try await line in bytes.lines {
                        continuation.yield(line)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    package func streamLinesUsingDelegate(_ request: URLRequest) -> AsyncStream<String> {
        let delegate = SSEDataDelegate()
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        let task = session.dataTask(with: request)

        let stream = AsyncStream<String> { continuation in
            delegate.onLine = { line in continuation.yield(line) }
            delegate.onComplete = { continuation.finish() }
            continuation.onTermination = { _ in
                task.cancel()
                session.invalidateAndCancel()
            }
            task.resume()
        }
        return stream
    }
}

private final class SSEDataDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    var onLine: ((String) -> Void)?
    var onComplete: (() -> Void)?
    private var buffer = ""

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let chunk = String(data: data, encoding: .utf8) else { return }
        buffer += chunk
        while let newlineRange = buffer.range(of: "\n") {
            let line = String(buffer[..<newlineRange.lowerBound])
            buffer = String(buffer[newlineRange.upperBound...])
            onLine?(line)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        onComplete?()
    }
}
