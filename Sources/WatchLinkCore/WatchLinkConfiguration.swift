import Foundation

public struct WatchLinkConfiguration: Sendable {
    public var transports: Set<TransportKind> = [.watchConnectivity, .http]
    public var bleServiceUUID: UUID?
    public var bleIPCharacteristicUUID: UUID?
    public var httpPort: UInt16 = 8188
    public var sseHeartbeatInterval: Duration = .seconds(15)
    public var pingInterval: Duration = .seconds(5)
    public var sweepInterval: Duration = .seconds(30)
    public var maxRetries: Int = 3
    public var maxPingFailures: Int = 3
    public var clock: AnyClock = AnyClock(ContinuousClock())
    public var logger: WatchLinkLogger = .osLog

    public enum TransportKind: Sendable, Hashable {
        case watchConnectivity
        case http
    }

    public init() {}
}
