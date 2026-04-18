/// Describes the current link state between the watch and phone.
///
/// Observe via `WatchLink.connectionState` (or `WatchLinkHost`'s equivalent).
/// State transitions are driven by heartbeats and transport reachability.
public enum ConnectionState: Sendable, Equatable, CustomStringConvertible {
    /// No connect attempt is in flight.
    case disconnected
    /// `connect()` has been called; waiting for the first heartbeat.
    case connecting
    /// Heartbeat received within the inactivity window; messages flow normally.
    case connected
    /// Inactivity timeout fired; reconnecting with exponential backoff.
    case reconnecting(attempt: Int)

    public var description: String {
        switch self {
        case .disconnected: "disconnected"
        case .connecting: "connecting"
        case .connected: "connected"
        case .reconnecting(let attempt): "reconnecting (attempt \(attempt))"
        }
    }
}
