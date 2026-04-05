public protocol WatchLinkMessage: Codable, Sendable {
    static var channel: Channel { get }
}
