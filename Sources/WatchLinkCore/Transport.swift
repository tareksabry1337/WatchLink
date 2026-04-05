import Foundation

package protocol Transport: Actor {
    var isReachable: Bool { get }
    var reachabilityChanges: AsyncStream<Bool> { get }
    func send(_ data: Data) async throws
    func incoming() -> AsyncStream<IncomingMessage>
    func start() async
    func stop() async
}
