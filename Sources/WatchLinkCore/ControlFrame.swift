package enum ControlFrame: Codable, Sendable {
    case ping
    case pong
    case ack(String)
}
