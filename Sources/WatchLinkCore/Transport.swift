import Foundation

package protocol Transport: Actor {
    var isReachable: Bool { get }
    var reachabilityChanges: AsyncStream<Bool> { get }
    func send(_ data: Data) async throws
    func query(_ data: Data) async throws -> Data
    func respondToQuery(frameID: String, data: Data) async
    func populateDiagnostics(_ diagnostics: inout WatchLinkDiagnostics) async
    func incoming() -> AsyncStream<IncomingMessage>
    func start() async
    func stop() async
}

extension Transport {
    package func query(_ data: Data) async throws -> Data {
        throw WatchLinkError.sendFailed("Transport does not support query")
    }
}
