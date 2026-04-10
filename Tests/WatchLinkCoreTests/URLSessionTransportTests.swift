import Testing
import Foundation
@testable import WatchLinkCore

@Suite("URLSession Transport")
struct URLSessionTransportTests {

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    // MARK: - performRequestUsingDataTask

    @Test("dataTask path returns data and response")
    func dataTaskReturnsData() async throws {
        let body = Data("hello".utf8)
        StubURLProtocol.setStub(Stub(data: body, statusCode: 200), for: "/datatask-ok")

        let session = makeSession()
        let url = try #require(URL(string: "http://test/datatask-ok"))
        let (data, response) = try await session.performRequestUsingDataTask(URLRequest(url: url))

        #expect(data == body)
        let http = try #require(response as? HTTPURLResponse)
        #expect(http.statusCode == 200)
    }

    @Test("dataTask path throws on network error")
    func dataTaskThrowsOnError() async throws {
        StubURLProtocol.setStub(Stub(error: URLError(.notConnectedToInternet)), for: "/datatask-error")

        let session = makeSession()
        let url = try #require(URL(string: "http://test/datatask-error"))

        do {
            _ = try await session.performRequestUsingDataTask(URLRequest(url: url))
            Issue.record("Expected error")
        } catch {
            #expect(error is URLError)
        }
    }

    // MARK: - streamLinesUsingDelegate

    @Test("delegate path streams lines from chunked data")
    func delegateStreamsLines() async throws {
        let ssePayload = "data: first\n\ndata: second\n\n"
        StubURLProtocol.setStub(Stub(data: Data(ssePayload.utf8), statusCode: 200), for: "/stream-lines")

        let session = makeSession()
        let url = try #require(URL(string: "http://test/stream-lines"))

        var lines: [String] = []
        for await line in session.streamLinesUsingDelegate(URLRequest(url: url)) {
            lines.append(line)
        }

        #expect(lines.contains("data: first"))
        #expect(lines.contains("data: second"))
    }

    @Test("delegate path finishes on completion")
    func delegateFinishesOnComplete() async throws {
        StubURLProtocol.setStub(Stub(data: Data("line\n".utf8), statusCode: 200), for: "/stream-finish")

        let session = makeSession()
        let url = try #require(URL(string: "http://test/stream-finish"))

        var count = 0
        for await _ in session.streamLinesUsingDelegate(URLRequest(url: url)) {
            count += 1
        }

        #expect(count == 1)
    }
}

// MARK: - URLProtocol Stub

private struct Stub {
    var data: Data?
    var statusCode: Int = 200
    var error: Error?
}

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var stubs: [String: Stub] = [:]

    static func setStub(_ stub: Stub, for path: String) {
        lock.withLock { stubs[path] = stub }
    }

    private static func stub(for path: String) -> Stub? {
        lock.withLock { stubs[path] }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url?.path ?? ""
        guard let stub = StubURLProtocol.stub(for: path) else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }

        if let error = stub.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        guard let url = request.url,
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: stub.statusCode,
                  httpVersion: "HTTP/1.1",
                  headerFields: nil
              ) else { return }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if let data = stub.data {
            client?.urlProtocol(self, didLoad: data)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
