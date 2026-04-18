import Foundation

/// A decoded message plus the opaque frame ID needed to reply to it.
///
/// Delivered via `messages(_:)` streams. Pass to `reply(with:to:)` to correlate a
/// response back to the original sender.
public struct ReceivedMessage<M: WatchLinkMessage>: Sendable {
    /// The decoded message payload.
    public let value: M
    package let frameID: String
}
