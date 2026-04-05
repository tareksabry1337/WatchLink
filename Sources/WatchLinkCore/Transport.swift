import Foundation

public protocol Transport: Actor {
    var isReachable: Bool { get }
    var reachabilityChanges: AsyncStream<Bool> { get }
    func send(_ data: Data) async throws
    func incoming() -> AsyncStream<Data>
    func start() async
    func stop() async
}
