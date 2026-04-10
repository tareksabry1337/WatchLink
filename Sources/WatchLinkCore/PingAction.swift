package enum PingAction: Sendable, Equatable {
    case sendPing
    case reconnect(attempt: Int)
}
