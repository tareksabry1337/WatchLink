import Foundation

package struct Frame: Codable, Sendable {
    package enum Kind: String, Codable, Sendable {
        case message
        case control
    }

    package let kind: Kind
    package let id: String
    package let channel: Channel?
    package let payload: Data

    package init<M: WatchLinkMessage>(wrapping message: M, encoder: JSONEncoder) throws {
        self.kind = .message
        self.id = UUID().uuidString
        self.channel = M.channel
        self.payload = try encoder.encode(message)
    }

    package init(control frame: ControlFrame, encoder: JSONEncoder) throws {
        self.kind = .control
        self.id = UUID().uuidString
        self.channel = nil
        self.payload = try encoder.encode(frame)
    }
}
