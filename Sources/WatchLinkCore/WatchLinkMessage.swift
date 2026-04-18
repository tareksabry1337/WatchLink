/// A message that can be sent between the watch and phone.
///
/// Define your own message types by conforming to `WatchLinkMessage`. The type is used
/// as the routing channel, so each message type must be unique in your app. Set
/// `Response` to another `WatchLinkMessage` if this message expects a reply; leave it
/// defaulted to `NoResponse` for fire-and-forget sends.
public protocol WatchLinkMessage: Codable, Sendable {
    /// The reply type the receiver is expected to send back.
    associatedtype Response: WatchLinkMessage = NoResponse
}

extension WatchLinkMessage {
    package static var channel: Channel { Channel(String(describing: Self.self)) }
}

/// Uninhabited type used as the default `Response` for fire-and-forget messages.
public struct NoResponse: WatchLinkMessage {
    private init() {}
}
