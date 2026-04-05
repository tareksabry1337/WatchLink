import Foundation

package protocol URLSessionProtocol {
    func data(for request: URLRequest, delegate: (any URLSessionTaskDelegate)?) async throws -> (Data, URLResponse)
    func bytes(for request: URLRequest, delegate: (any URLSessionTaskDelegate)?) async throws -> (URLSession.AsyncBytes, URLResponse)
}

extension URLSession: URLSessionProtocol {}
