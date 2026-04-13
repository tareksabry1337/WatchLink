import Foundation

@WatchLinkActor
package protocol Transport: Sendable {
    var isReachable: Bool { get }
    var reachabilityChanges: AsyncStream<Bool> { get }
    func send(_ data: Data) async throws
    func request(_ data: Data) async throws -> Data
    func reply(to frameID: String, with data: Data) async
    func populateDiagnostics(_ diagnostics: inout WatchLinkDiagnostics)
    func incoming() -> AsyncStream<IncomingMessage>
    func start()
    func stop()
}
