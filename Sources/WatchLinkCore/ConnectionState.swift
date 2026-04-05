public enum ConnectionState: Sendable, Equatable, CustomStringConvertible {
    case disconnected
    case connecting
    case connected
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
