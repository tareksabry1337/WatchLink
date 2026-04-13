import Foundation

public struct WatchLinkConfiguration: Sendable {
    public var transports: Set<TransportKind> = [.watchConnectivity, .http]
    public var bleServiceUUID: UUID?
    public var bleIPCharacteristicUUID: UUID?
    public var httpPort: UInt16 = 8188
    public var pingInterval: Duration = .seconds(5)
    package var sseHeartbeatInterval: Duration = .seconds(15)
    package var retryInterval: Duration = .seconds(5)
    public var maxPingFailures: Int = 3
    public var logger: WatchLinkLogger = .osLog
    package var clock: AnyClock = AnyClock()

    public enum TransportKind: Sendable, Hashable {
        case watchConnectivity
        case http
    }

    public init() {}
}
