import Foundation

/// Configuration passed to `WatchLink` and `WatchLinkHost` initializers.
///
/// Mutate inside the trailing closure to customize transports, BLE UUIDs, HTTP port,
/// heartbeat cadence, and logging.
public struct WatchLinkConfiguration: Sendable {
    /// Transports to enable. `.http` also implies BLE IP discovery.
    public var transports: Set<TransportKind> = [.watchConnectivity, .http]
    /// BLE service UUID used for the phone's IP-advertising characteristic.
    ///
    /// Required when `.http` is enabled. Generate once and reuse on both sides.
    public var bleServiceUUID: UUID?
    /// BLE characteristic UUID carrying the phone's local IP address.
    ///
    /// Required when `.http` is enabled.
    public var bleIPCharacteristicUUID: UUID?
    /// TCP port the host's HTTP server binds to. Both sides must agree.
    public var httpPort: UInt16 = 8188
    /// How often the watch pings the phone to drive the connection-state machine.
    public var pingInterval: Duration = .seconds(5)
    package var sseHeartbeatInterval: Duration = .seconds(15)
    package var retryInterval: Duration = .seconds(5)
    /// Consecutive missed pings before the state machine transitions to `.reconnecting`.
    public var maxPingFailures: Int = 3
    /// Logger for transport diagnostics. Defaults to Apple unified logging.
    public var logger: WatchLinkLogger = .osLog
    package var clock: AnyClock = AnyClock()

    /// Which underlying transport to enable.
    public enum TransportKind: Sendable, Hashable {
        /// Apple's `WCSession` (always on). Reliable when reachable but `isReachable` lies.
        case watchConnectivity
        /// HTTP + SSE over the local network. Enables BLE IP discovery automatically.
        case http
    }

    public init() {}
}
