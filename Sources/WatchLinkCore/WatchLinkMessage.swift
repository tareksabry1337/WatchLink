public protocol WatchLinkMessage: Codable, Sendable {
    static var channel: Channel { get }
}

public protocol WatchLinkQuery: WatchLinkMessage {
    associatedtype Response: WatchLinkMessage
}
