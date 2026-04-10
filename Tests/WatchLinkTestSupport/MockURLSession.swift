import Foundation
@testable import WatchLinkCore

public final class MockURLSession: URLSessionProtocol, @unchecked Sendable {
    public var responseData = Data()
    public var responseCode = 200
    public var shouldFail = false
    public var receivedRequests: [URLRequest] = []

    public init() {}

    public func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        receivedRequests.append(request)
        if shouldFail {
            throw WatchLinkError.sendFailed("Mock URL failure")
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: responseCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (responseData, response)
    }

    public func streamLines(_ request: URLRequest) -> AsyncStream<String> {
        AsyncStream { $0.finish() }
    }
}
