import Foundation

public struct ReceivedMessage<M: WatchLinkMessage>: Sendable {
    public let value: M
    package let frameID: String
}
