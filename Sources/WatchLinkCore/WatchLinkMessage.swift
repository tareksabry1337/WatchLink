public protocol WatchLinkMessage: Codable, Sendable {
    associatedtype Response: WatchLinkMessage = NoResponse
}

extension WatchLinkMessage {
    package static var channel: Channel { Channel(String(describing: Self.self)) }
}

/// Uninhabited type used as the default `Response` for fire-and-forget messages.
public struct NoResponse: WatchLinkMessage {
    private init() {}
}
