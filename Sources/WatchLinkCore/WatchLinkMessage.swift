public protocol WatchLinkMessage: Codable, Sendable {
    associatedtype Response: WatchLinkMessage = NoResponse
    static var channel: Channel { get }
}

/// Uninhabited type used as the default `Response` for fire-and-forget messages.
public enum NoResponse: WatchLinkMessage {
    public static var channel: Channel { fatalError("NoResponse is not a real message") }

    public func encode(to encoder: any Encoder) throws {}

    public init(from decoder: any Decoder) throws {
        fatalError("NoResponse cannot be decoded")
    }
}
